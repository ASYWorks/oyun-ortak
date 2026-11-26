import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { bellekDepo } from "../kayit/index.ts";
import { adBicimiUygun, googleNonce, hesapBaslat, KayitHatasi, misafirAdi, MISAFIR_ADI } from "./index.ts";

test("Google nonce: özet ham değerin SHA-256'sı, her çağrıda yeni", async () => {
  const a = await googleNonce();
  const b = await googleNonce();
  assert.match(a.ham, /^[0-9a-f]{64}$/);
  assert.equal(a.ozet, createHash("sha256").update(a.ham).digest("hex"));
  assert.notEqual(a.ham, b.ham);
});

test("giriş seçenekleri: iOS'ta Apple ve Google, Android'de Google; e-posta yedek, misafir en sonda", async () => {
  const { girisSecenekleri, GIRIS_RENKLERI, GIRIS_METINLERI, GOOGLE_G_SVG } = await import("./index.ts");
  assert.deepEqual(girisSecenekleri({ platform: "ios" }), ["apple", "google", "eposta", "misafir"]);
  assert.deepEqual(girisSecenekleri({ platform: "android" }), ["google", "eposta", "misafir"]);
  assert.deepEqual(girisSecenekleri({ platform: "web", apple: true }), ["google", "apple", "eposta", "misafir"]);
  assert.deepEqual(girisSecenekleri({ platform: "android", misafir: false }), ["google", "eposta"]);
  assert.equal(GIRIS_RENKLERI.google.acik.kenar, "#747775");
  assert.equal(GIRIS_METINLERI.tr.google, "Google ile devam et");
  for (const r of ["#EA4335", "#4285F4", "#FBBC05", "#34A853"]) assert.ok(GOOGLE_G_SVG.includes(r));
});

test("misafir adı: # + 5 karakter, karışan karakter yok, seçilen ad biçimine uymaz", () => {
  const goruldu = new Set<string>();
  for (let i = 0; i < 2000; i++) {
    const a = misafirAdi();
    assert.match(a, MISAFIR_ADI);
    assert.doesNotMatch(a, /[O0I1]/);
    goruldu.add(a);
  }
  assert.ok(goruldu.size > 1900);
});


test("ortak ad kuralı", () => {
  for (const iyi of ["Işık", "kara_kedi", "ali.veli", "a1b", "x".repeat(20), "Oyuncu42", "ç_ğ.ş"]) assert.ok(adBicimiUygun(iyi), iyi);
  for (const kotu of ["ab", "x".repeat(21), "iki ad", "_ali", "ali.", "ali__veli", "a._b", "123", "kara-kedi", "#K7P2X", "a<b>c", "ab😀"])
    assert.ok(!adBicimiUygun(kotu), kotu);
});

// D03: web misafir devri. Sahte auth (gerçek SDK şekli) ve hesap_devral; yanıt sırası test içinden belirlenir.
function devirTaklidi() {
  type Oturum = { user: { id: string; is_anonymous: boolean }; access_token: string } | null;
  const s = {
    oturum: { user: { id: "anon", is_anonymous: true }, access_token: "jeton-anon" } as Oturum,
    cagri: [] as { kod: unknown; yetki: string; kim: string | null }[],
    yanitlar: [] as ({ data: unknown; error: { message: string } | null } | "ag")[],
    bekle: null as Promise<void> | null,
  };
  const kalici = (id: string): Oturum => ({ user: { id, is_anonymous: false }, access_token: `jeton-${id}` });
  const supabase = {
    auth: {
      getSession: async () => ({ data: { session: s.oturum } }),
      signInWithOAuth: async () => ({ error: null }),
    },
    schema: () => ({
      rpc: (ad: string, arg: Record<string, unknown>) => {
        if (ad === "devir_kodu_al") return Promise.resolve({ data: "KOD-1", error: null });
        return {
          setHeader: async (_h: string, deger: string) => {
            s.cagri.push({ kod: arg.p_kod, yetki: deger, kim: s.oturum?.user.id ?? null });
            if (s.bekle) await s.bekle;
            const y = s.yanitlar.shift() ?? { data: { oyunlar: ["o"], skorlar_tasindi: true }, error: null };
            if (y === "ag") throw new TypeError("Failed to fetch");
            return y;
          },
        };
      },
    }),
  } as unknown as Parameters<typeof hesapBaslat>[0]["supabase"];
  const depo = bellekDepo();
  const h = hesapBaslat({ oyunId: "o", supabase, depo });
  return { s, kalici, depo, h };
}

test("D03: geçici hatada kayıt silinmez, aynı hesapta yeniden denenir; başarıda temizlenir; jeton açıkça hedefin", async () => {
  const { s, kalici, depo, h } = devirTaklidi();
  await h.webIleGir("google", "https://x/");
  s.oturum = kalici("A");
  s.yanitlar.push("ag");
  assert.deepEqual(await h.webDonusunuTamamla(), { devredilen: [], devirBasarisiz: true });
  assert.ok(depo.veri.get("oyun-ortak:devir"), "geçici hatada kayıt kalır");
  assert.equal(JSON.parse(depo.veri.get("oyun-ortak:devir")!).sahip, "A");
  const r = await h.webDonusunuTamamla();
  assert.deepEqual(r, { devredilen: ["o"], skorlarTasindi: true });
  assert.deepEqual(s.cagri.map((c) => [c.kod, c.yetki]), [["KOD-1", "Bearer jeton-A"], ["KOD-1", "Bearer jeton-A"]]);
  assert.equal(depo.veri.has("oyun-ortak:devir"), false, "başarıda temizlenir");
});

test("D03: kayıt başka kalıcı hesapta denenmez; kesin devir_kodu_gecersiz kaydı temizler", async () => {
  const { s, kalici, depo, h } = devirTaklidi();
  await h.webIleGir("google", "https://x/");
  s.oturum = kalici("A");
  s.yanitlar.push({ data: null, error: { message: "upstream 502" } });
  await h.webDonusunuTamamla(); // A'ya bağlandı, geçici hata
  s.oturum = kalici("B");
  assert.equal(await h.webDonusunuTamamla(), null);
  assert.equal(s.cagri.length, 1, "B ile çağrı yok");
  s.oturum = kalici("A");
  s.yanitlar.push({ data: null, error: { message: "devir_kodu_gecersiz" } });
  assert.deepEqual(await h.webDonusunuTamamla(), { devredilen: [], devirBasarisiz: true });
  assert.equal(depo.veri.has("oyun-ortak:devir"), false);
});

test("D03: süre dolan kayıt ağa gitmeden temizlenir; eski ham kod ilk kullanımda kabul edilir", async () => {
  const { s, kalici, depo, h } = devirTaklidi();
  s.oturum = kalici("A");
  depo.veri.set("oyun-ortak:devir", JSON.stringify({ id: "x", kod: "ESKI", olusturma: Date.now() - 31 * 60_000, sahip: null }));
  assert.deepEqual(await h.webDonusunuTamamla(), { devredilen: [], devirBasarisiz: true });
  assert.equal(s.cagri.length, 0);
  assert.equal(depo.veri.has("oyun-ortak:devir"), false);
  depo.veri.set("oyun-ortak:devir", "HAM-KOD"); // eski sürümün biçimi
  assert.deepEqual(await h.webDonusunuTamamla(), { devredilen: ["o"], skorlarTasindi: true });
  assert.equal(s.cagri[0]!.kod, "HAM-KOD");
  assert.equal(depo.veri.has("oyun-ortak:devir"), false);
});

test("D03 (inceleme 2): süresi dolan kayıt misafire ve başka kalıcı hesaba sahte 'devir başarısız' göstermez, sessizce silinir", async () => {
  const { s, kalici, depo, h } = devirTaklidi();
  const eski = (sahip: string | null) =>
    depo.veri.set("oyun-ortak:devir", JSON.stringify({ id: "x", kod: "K", olusturma: Date.now() - 31 * 60_000, sahip }));
  eski(null); // girişten vazgeçip misafir kaldı
  assert.equal(await h.webDonusunuTamamla(), null);
  assert.equal(depo.veri.has("oyun-ortak:devir"), false);
  eski("A"); // A'nın kaydı, B açık
  s.oturum = kalici("B");
  assert.equal(await h.webDonusunuTamamla(), null);
  assert.equal(depo.veri.has("oyun-ortak:devir"), false);
  eski("B"); // kendi kaydı: bildirilir
  assert.deepEqual(await h.webDonusunuTamamla(), { devredilen: [], devirBasarisiz: true });
  assert.equal(s.cagri.length, 0);
});

test("D03: eşzamanlı dönüş tek devir atar; yanıt beklerken hesap değişirse sonuç kullanılmaz; yeni kayıt eski işlemce silinmez", async () => {
  const { s, kalici, depo, h } = devirTaklidi();
  await h.webIleGir("google", "https://x/");
  s.oturum = kalici("A");
  let ac!: () => void;
  s.bekle = new Promise<void>((r) => { ac = r; });
  const p1 = h.webDonusunuTamamla();
  const p2 = h.webDonusunuTamamla();
  for (let i = 0; i < 50 && s.cagri.length === 0; i++) await new Promise((r) => setTimeout(r, 0));
  // yanıt beklerken: daha yeni bir devir kaydı yazılıyor ve oturum başka hesaba geçiyor
  depo.veri.set("oyun-ortak:devir", JSON.stringify({ id: "yeni", kod: "KOD-2", olusturma: Date.now(), sahip: null }));
  s.oturum = kalici("B");
  ac();
  const [r1, r2] = await Promise.all([p1, p2]);
  assert.equal(s.cagri.length, 1, "tek devir çağrısı");
  assert.equal(r1, null, "hesap değişti: sonuç kullanılmaz");
  assert.equal(r2, r1);
  assert.equal(JSON.parse(depo.veri.get("oyun-ortak:devir")!).id, "yeni", "daha yeni kayıt silinmedi");
});

test("D03: sahiplik depoya yazılamazsa RPC çağrılmaz; kayıt sahipsiz kalır ve sonra doğru hesapta denenir", async () => {
  const { s, kalici, depo, h } = devirTaklidi();
  await h.webIleGir("google", "https://x/");
  s.oturum = kalici("A");
  const yaz = depo.yaz;
  depo.yaz = async () => { throw new Error("depo-dolu"); };
  assert.equal(await h.webDonusunuTamamla(), null);
  assert.equal(s.cagri.length, 0, "sahiplik yazılmadan çağrı yok");
  assert.equal(JSON.parse(depo.veri.get("oyun-ortak:devir")!).sahip, null);
  depo.yaz = yaz;
  assert.deepEqual(await h.webDonusunuTamamla(), { devredilen: ["o"], skorlarTasindi: true });
  assert.equal(s.cagri[0]!.yetki, "Bearer jeton-A");
});

test("D03: RPC geçici hata fırlatırken hesap değiştiyse sonuç yeni oturuma dönmez", async () => {
  const { s, kalici, depo, h } = devirTaklidi();
  await h.webIleGir("google", "https://x/");
  s.oturum = kalici("A");
  let ac!: () => void;
  s.bekle = new Promise<void>((r) => { ac = r; });
  s.yanitlar.push("ag");
  const p = h.webDonusunuTamamla();
  for (let i = 0; i < 50 && s.cagri.length === 0; i++) await new Promise((r) => setTimeout(r, 0));
  s.oturum = kalici("B");
  ac();
  assert.equal(await p, null);
  assert.equal(JSON.parse(depo.veri.get("oyun-ortak:devir")!).sahip, "A", "kayıt A'ya bağlı kalır");
});

function bulutTaklidi(rpc: (ad: string, arg: Record<string, unknown>) => Promise<unknown>) {
  const kim = crypto.randomUUID();
  const supabase = {
    auth: { getSession: async () => ({ data: { session: { user: { id: kim } } } }) },
    schema: () => ({ rpc }),
  } as unknown as Parameters<typeof hesapBaslat>[0]["supabase"];
  return {
    kim,
    bulut: hesapBaslat({ oyunId: "deneme", supabase, depo: bellekDepo() })
      .bulutKaydi<{ puan: number }>(),
  };
}

test("MD-24: doğrulamalı çağrı reddedildiğinde eski çağrıya düşmez", async () => {
  const cagrilar: string[] = [];
  const { kim, bulut } = bulutTaklidi(async (ad) => {
    cagrilar.push(ad);
    if (cagrilar.length === 1) return { data: { veri: { puan: 1 }, surum: 1 }, error: null };
    return { data: null, error: { message: "hesap_degisti" } };
  });

  // inceleme 4: sunucunun hesap_degisti hatası da KayitHatasi olarak gelir (KZ-1: oyunlar kod'a bakar)
  await assert.rejects(bulut.birlestir({ puan: 2 }, (yerel) => ({ kayit: yerel }), { kim }),
    (e) => e instanceof KayitHatasi && e.kod === "hesap_degisti");
  assert.deepEqual(cagrilar, ["kayit_oku_hesapli", "kayit_yaz_hesapli"]);
});

test("MD-24: göç eksikse eski RPC çağrılmadan hata döner", async () => {
  const cagrilar: string[] = [];
  const { kim, bulut } = bulutTaklidi(async (ad) => {
    cagrilar.push(ad);
    return { data: null, error: { message: "Could not find the function in the schema cache" } };
  });

  await assert.rejects(bulut.birlestir({ puan: 2 }, (yerel) => ({ kayit: yerel }), { kim }), /kayit_hesapli_yok/);
  assert.deepEqual(cagrilar, ["kayit_oku_hesapli"]);
});

test("KZ-1: kayıt hataları KayitHatasi (kod alanı) olarak atılır; mesaj aynı kalır", async () => {
  // Her yazım çakışır (null döner): dört denemeden sonra kayit_cakisma.
  const { kim, bulut } = bulutTaklidi(async (ad) =>
    ad === "kayit_oku_hesapli" ? { data: { veri: { puan: 1 }, surum: 1 }, error: null } : { data: null, error: null });
  const e = await bulut.birlestir({ puan: 2 }, (yerel) => ({ kayit: yerel }), { kim }).then(() => null, (x: unknown) => x);
  assert.ok(e instanceof KayitHatasi);
  assert.equal((e as KayitHatasi).kod, "kayit_cakisma");
  assert.equal((e as Error).message, "kayit_cakisma");
  // Beklenen hesap değilse: hesap_degisti
  const e2 = await bulut.birlestir({ puan: 2 }, (yerel) => ({ kayit: yerel }), { kim: "baska" }).then(() => null, (x: unknown) => x);
  assert.ok(e2 instanceof KayitHatasi);
  assert.equal((e2 as KayitHatasi).kod, "hesap_degisti");
});

test("KK-7: ağsız çıkışta oturum cihazdan silinir", async () => {
  const kapsamlar: (string | undefined)[] = [];
  const supabase = {
    auth: {
      signOut: async (o?: { scope?: string }) => {
        kapsamlar.push(o?.scope);
        return { error: o?.scope === "local" ? null : new Error("Failed to fetch") };
      },
    },
  } as unknown as Parameters<typeof hesapBaslat>[0]["supabase"];
  await hesapBaslat({ oyunId: "deneme", supabase, depo: bellekDepo() }).cikis();
  assert.deepEqual(kapsamlar, [undefined, "local"]);
});
