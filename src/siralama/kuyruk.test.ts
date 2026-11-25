import { test } from "node:test";
import assert from "node:assert/strict";
import { siralamaBaslat } from "./index.ts";
import { bellekDepo } from "../kayit/index.ts";

// Sahte Supabase (gerçek SDK şekli: session.user.id/is_anonymous, access_token): oturumdaki kullanıcı değiştirilebilir,
// ağ açılıp kapanabilir; giden gönderimler kaydedilir.
function sahte() {
  const s = { kullanici: "A" as string | null, ag: true, giden: [] as { kim: string | null; govde: unknown }[] };
  const oturum = () => (s.kullanici ? { user: { id: s.kullanici, is_anonymous: false }, access_token: `jeton-${s.kullanici}` } : null);
  const sb = {
    auth: {
      getSession: async () => ({ data: { session: oturum() } }),
      signInAnonymously: async () => ({ data: { session: null, user: null }, error: null }),
    },
    functions: {
      invoke: async (_fn: string, o: { body: unknown }) => {
        if (!s.ag) return { data: null, error: { context: undefined } };
        s.giden.push({ kim: s.kullanici, govde: o.body });
        return { data: { ok: true }, error: null };
      },
    },
  };
  return { s, sb };
}

test("O15: A'nın kuyruktaki gönderimi B'nin oturumuyla gitmez, A dönünce gider", async () => {
  const { s, sb } = sahte();
  const depo = bellekDepo();
  const sir = siralamaBaslat({ supabase: sb as never, oyunId: "o", depo });
  s.ag = false;
  assert.equal((await sir.gonder({ x: 1 })).bekliyor, true);
  s.ag = true;
  s.kullanici = "B";
  await sir.bosalt();
  assert.equal(s.giden.length, 0);
  assert.equal(await sir.bekleyenSayisi(), 1);
  await sir.gonder({ x: 2 });
  assert.deepEqual(s.giden.map((g) => g.kim), ["B"]);
  s.kullanici = "A";
  await sir.bosalt();
  assert.deepEqual(s.giden.map((g) => g.kim), ["B", "A"]);
  assert.equal(await sir.bekleyenSayisi(), 0);
});

// D02 için ayrıntılı sahte: oturum (kalıcı/anonim, jeton), anonim giriş, elle yanıtlanan invoke, gecikmeli cihaz okuması.
function sahte2() {
  type Oturum = { user: { id: string; is_anonymous: boolean }; access_token: string } | null;
  const s = {
    oturum: { user: { id: "A", is_anonymous: false }, access_token: "jeton-A" } as Oturum,
    giden: [] as { kim: string | null; yetki: string | undefined; govde: Record<string, unknown> }[],
    bekle: false,
    anonimSayac: 0,
    anonimSecenek: [] as unknown[],
  };
  let coz: ((v: { data: unknown; error: null }) => void) | null = null;
  const kalici = (id: string): Oturum => ({ user: { id, is_anonymous: false }, access_token: `jeton-${id}` });
  const sb = {
    auth: {
      getSession: async () => ({ data: { session: s.oturum } }),
      signInAnonymously: async (o?: { options?: { captchaToken?: string } }) => {
        s.anonimSecenek.push(o?.options);
        const id = `G${++s.anonimSayac}`;
        s.oturum = { user: { id, is_anonymous: true }, access_token: `jeton-${id}` };
        return { data: { session: s.oturum, user: s.oturum.user }, error: null }; // gerçek SDK şekli
      },
    },
    functions: {
      invoke: (_fn: string, o: { body: Record<string, unknown>; headers?: Record<string, string> }) => {
        s.giden.push({ kim: s.oturum?.user.id ?? null, yetki: o.headers?.Authorization, govde: o.body });
        if (!s.bekle) return Promise.resolve({ data: { ok: true }, error: null });
        return new Promise((r) => { coz = r; });
      },
    },
  };
  const yanitla = () => { const c = coz; coz = null; c?.({ data: { ok: true }, error: null }); };
  return { s, sb, kalici, yanitla };
}
const bekleyinceye = async (kosul: () => boolean) => { for (let i = 0; i < 200 && !kosul(); i++) await new Promise((r) => setTimeout(r, 0)); };

test("D02: aynı hesapta normal sonuç uygulanır; gönderim o oturumun jetonuna sabitlenir", async () => {
  const { s, sb } = sahte2();
  const gelen: string[] = [];
  const sir = siralamaBaslat({ supabase: sb as never, oyunId: "o", depo: bellekDepo(), sonuc: (r) => gelen.push(r.runId) });
  const r = await sir.gonder({ x: 1 });
  assert.equal(r.bekliyor, false);
  assert.equal(r.durum, 200);
  assert.deepEqual(gelen, [r.runId]);
  assert.equal(s.giden[0]!.yetki, "Bearer jeton-A");
  assert.equal(await sir.bekleyenSayisi(), 0);
});

test("D02: yanıt beklerken hesap değişirse sonuç yeni oturumda uygulanmaz, başarı dönmez; sahibi dönünce aynı runId ile gider", async () => {
  const { s, sb, kalici, yanitla } = sahte2();
  const gelen: { runId: string; kim: string | null }[] = [];
  const sir = siralamaBaslat({ supabase: sb as never, oyunId: "o", depo: bellekDepo(), sonuc: (r) => gelen.push({ runId: r.runId, kim: s.oturum?.user.id ?? null }) });
  s.bekle = true;
  const p = sir.gonder({ x: 1 });
  await bekleyinceye(() => s.giden.length === 1);
  assert.equal(s.giden[0]!.yetki, "Bearer jeton-A");
  s.oturum = kalici("B"); // yanıt dönmeden hesap değişti
  yanitla();
  const r = await p;
  assert.equal(r.bekliyor, true, "susturulan gönderim başarı dönmez");
  assert.deepEqual(gelen, [], "B oturumunda sonuç işlenmez");
  assert.equal(await sir.bekleyenSayisi(), 1);
  assert.equal(s.giden.length, 1, "B'nin oturumuyla yeniden gitmez");
  s.oturum = kalici("A");
  s.bekle = false;
  await sir.bosalt();
  assert.equal(s.giden.length, 2);
  assert.equal(s.giden[1]!.govde.runId, s.giden[0]!.govde.runId, "aynı runId");
  assert.equal(s.giden[1]!.yetki, "Bearer jeton-A");
  assert.deepEqual(gelen, [{ runId: r.runId, kim: "A" }]);
  assert.equal(await sir.bekleyenSayisi(), 0);
});

test("D02: cihaz kimliği yüklenirken hesap değişirse kayıt yeni hesapla gitmez", async () => {
  const { s, sb, kalici } = sahte2();
  const ic = bellekDepo();
  const tut: { coz: (() => void) | null } = { coz: null };
  const depo = { ...ic, oku: async (k: string) => {
    if (k === "oyun-ortak:cihaz") await new Promise<void>((r) => { tut.coz = r; });
    return ic.oku(k);
  } };
  const sir = siralamaBaslat({ supabase: sb as never, oyunId: "o", depo: depo as never });
  const p = sir.gonder({ x: 1 });
  await bekleyinceye(() => tut.coz !== null);
  s.oturum = kalici("B");
  tut.coz?.();
  const r = await p;
  assert.equal(r.bekliyor, true);
  assert.equal(s.giden.length, 0);
  assert.equal(await sir.bekleyenSayisi(), 1);
});

test("D02: sahipsiz eski kayıt kalıcı hesaba yazılmaz", async () => {
  const { s, sb, kalici } = sahte2();
  const depo = bellekDepo();
  await depo.yaz("oyun-ortak:gonderim:o", JSON.stringify([{ runId: "eski-1", govde: { x: 0 }, eklendi: Date.now() }]));
  s.oturum = kalici("B");
  const sir = siralamaBaslat({ supabase: sb as never, oyunId: "o", depo });
  const r = await sir.bosalt();
  assert.deepEqual(r, []);
  assert.equal(s.giden.length, 0);
  assert.equal(await sir.bekleyenSayisi(), 1);
});

test("D02: misafir: oturumsuz gönderim anonim hesap açar ve ona bağlanır; çevrimdışı misafir kaydı sonra açılan kalıcı hesaba gitmez", async () => {
  const { s, sb, kalici } = sahte2();
  s.oturum = null;
  const sir = siralamaBaslat({ supabase: sb as never, oyunId: "o", depo: bellekDepo() });
  const r = await sir.gonder({ x: 1 });
  assert.equal(r.bekliyor, false);
  assert.equal(s.giden[0]!.kim, "G1");
  assert.equal(s.giden[0]!.yetki, "Bearer jeton-G1");
  // çevrimdışı misafir kaydı: oturumsuz kuyruğa giriyor, gönderilmeden kalıcı hesap açılıyor
  const sir2 = siralamaBaslat({ supabase: sb as never, oyunId: "o2", depo: bellekDepo() });
  s.oturum = null;
  const ag = sb.functions.invoke;
  sb.functions.invoke = (() => Promise.resolve({ data: null, error: { context: undefined } })) as never; // ağ yok
  const sinir = s.anonimSayac;
  assert.equal((await sir2.gonder({ x: 2 })).bekliyor, true);
  sb.functions.invoke = ag;
  // ağsız denemede anonim hesap açıldı ve kayıt ona bağlandı; kullanıcı şimdi kalıcı hesaba geçiyor
  assert.equal(s.anonimSayac, sinir + 1);
  s.oturum = kalici("B");
  const onceki = s.giden.length;
  await sir2.bosalt();
  assert.equal(s.giden.length, onceki, "misafirin kaydı B'ye gitmez");
  assert.equal(await sir2.bekleyenSayisi(), 1);
});

test("D02: captcha beklerken kalıcı hesap açılırsa anonim giriş yapılmaz (oturum ezilmez) ve misafir kaydı ona gitmez", async () => {
  const { s, sb, kalici } = sahte2();
  s.oturum = null;
  const sir = siralamaBaslat({
    supabase: sb as never, oyunId: "o", depo: bellekDepo(),
    captcha: async () => { s.oturum = kalici("B"); return "j1"; }, // jeton beklenirken kullanıcı kalıcı hesapla girdi
  });
  const r = await sir.gonder({ x: 1 });
  assert.equal(r.bekliyor, true);
  assert.equal(s.anonimSayac, 0, "signInAnonymously çağrılmadı");
  assert.equal(s.oturum?.user.id, "B", "yeni oturum ezilmedi");
  assert.equal(s.giden.length, 0);
  assert.equal(await sir.bekleyenSayisi(), 1);
});

test("D02: oturumda jeton yoksa gönderim yapılmaz (SDK'nın örtük oturumuna düşülmez)", async () => {
  const { s, sb } = sahte2();
  s.oturum = { user: { id: "A", is_anonymous: false }, access_token: "" };
  const sir = siralamaBaslat({ supabase: sb as never, oyunId: "o", depo: bellekDepo() });
  const r = await sir.gonder({ x: 1 });
  assert.equal(r.bekliyor, true);
  assert.equal(s.giden.length, 0);
  assert.equal(await sir.bekleyenSayisi(), 1);
  s.oturum = { user: { id: "A", is_anonymous: false }, access_token: "jeton-A" };
  await sir.bosalt();
  assert.equal(s.giden.length, 1);
  assert.equal(s.giden[0]!.yetki, "Bearer jeton-A");
});

test("GC-1: kuyruktaki önceki gönderimin sonucu da işlenir; süren boşaltmaya denk gelen gönderim de gider", async () => {
  const { s, sb } = sahte();
  const gelen: unknown[] = [];
  const sir = siralamaBaslat({ supabase: sb as never, oyunId: "o", depo: bellekDepo(), sonuc: (r) => gelen.push((r.veri as { ok?: boolean })?.ok ?? r.durum) });
  s.ag = false;
  await sir.gonder({ x: 1 });
  s.ag = true;
  const r = await sir.gonder({ x: 2 });
  assert.equal(r.bekliyor, false);
  assert.deepEqual(gelen, [0, true, true]); // ağsız deneme, sonra iki gönderim
  // süren boşaltma sırasında gelen gönderim
  const bos = sir.bosalt();
  const r2 = await sir.gonder({ x: 3 });
  await bos;
  assert.equal(r2.bekliyor, false);
  assert.equal(await sir.bekleyenSayisi(), 0);
});

test("7 günden eski, gönderilemeyen kayıt kuyruktan düşer; taze olan bekler", async () => {
  const { s, sb } = sahte();
  const depo = bellekDepo();
  const eski = Date.now() - 8 * 86_400_000;
  await depo.yaz("oyun-ortak:gonderim:o", JSON.stringify([
    { runId: "eski", govde: { x: 1 }, eklendi: eski, kullanici: "A" },
    { runId: "taze", govde: { x: 2 }, eklendi: Date.now(), kullanici: "A" },
  ]));
  s.kullanici = "B";
  const sir = siralamaBaslat({ supabase: sb as never, oyunId: "o", depo });
  await sir.bosalt();
  assert.equal(s.giden.length, 0);
  assert.equal(await sir.bekleyenSayisi(), 1);
  s.kullanici = "A";
  await sir.bosalt();
  assert.deepEqual(s.giden.map((g) => (g.govde as { runId: string }).runId), ["taze"]);
});
