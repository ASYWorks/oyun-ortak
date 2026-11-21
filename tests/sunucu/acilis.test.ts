// Göç 20261120006500: ortak.acilis tek istekte ben + sürüm damgaları. Değişmeyen damga sabit kalır, her değişiklik yalnız
// kendi damgasını değiştirir, başka oyuncunun işlemi damgaya dokunmaz, girişsiz reddedilir.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { hesapBaslat } from "../../src/hesap/index.ts";
import { bellekDepo } from "../../src/kayit/index.ts";
import { bugun, istemci, kaliciGir, sql } from "./yardimci.ts";

after(() => sql.end());

async function oyuncu() {
  const c = istemci();
  const h = hesapBaslat({ supabase: c, oyunId: "deneme", depo: bellekDepo() });
  const id = await kaliciGir(h);
  return { c, h, id };
}

test("acilis: ben + damgalar; değişmeyen sabit, değişen yalnız kendi damgası, başkası etkilemez", async () => {
  const a = await oyuncu(), b = await oyuncu();
  const ilk = await a.h.acilis();
  assert.equal(ilk.ben.anonim, false);
  assert.deepEqual(Object.keys(ilk.surum).sort(), ["haklar", "kayit", "oduller", "profil"]);
  assert.deepEqual(await a.h.acilis(), ilk, "hiçbir şey değişmedi: damgalar aynı");

  // B'nin her şeyi A'nın damgalarını değiştirmez
  await b.c.schema("ortak").rpc("odul_kaydet", { p_oyun: "deneme", p_oduller: [{ odul: "rozet-b" }] });
  await b.c.schema("ortak").rpc("kayit_yaz", { p_oyun: "deneme", p_veri: { b: 1 }, p_surum: 0 });
  await sql`insert into ortak.skorlar (oyun_id, kullanici_id, tur, donem, puan, run_id) values ('deneme', ${b.id}, 'gunluk', ${bugun()}, 3, gen_random_uuid())`;
  assert.deepEqual((await a.h.acilis()).surum, ilk.surum, "başkasının işlemi damgaya dokunmaz");

  // ödül → oduller ve profil değişir, haklar ve kayıt aynı
  await a.c.schema("ortak").rpc("odul_kaydet", { p_oyun: "deneme", p_oduller: [{ odul: "rozet-a" }] });
  const s1 = (await a.h.acilis()).surum;
  assert.notEqual(s1.oduller, ilk.surum.oduller);
  assert.notEqual(s1.profil, ilk.surum.profil);
  assert.equal(s1.haklar, ilk.surum.haklar);
  assert.equal(s1.kayit, ilk.surum.kayit);

  // skor → profil değişir, ödül aynı
  await sql`insert into ortak.skorlar (oyun_id, kullanici_id, tur, donem, puan, run_id) values ('deneme', ${a.id}, 'gunluk', ${bugun()}, 5, gen_random_uuid())`;
  const s2 = (await a.h.acilis()).surum;
  assert.notEqual(s2.profil, s1.profil);
  assert.equal(s2.oduller, s1.oduller);

  // profil ayarı → profil değişir
  await a.c.schema("ortak").rpc("profil_ayari", { p_oyun: "deneme", p_gizli: true });
  const s3 = (await a.h.acilis()).surum;
  assert.notEqual(s3.profil, s2.profil);

  // hak → haklar değişir
  await sql`insert into ortak.haklar (oyun_id, kullanici_id, hak, durum, kaynak) values ('deneme', ${a.id}, 'tam', 'aktif', 'elle')`;
  const s4 = (await a.h.acilis()).surum;
  assert.notEqual(s4.haklar, s3.haklar);
  assert.equal(s4.profil, s3.profil);

  // bulut kaydı → kayit = sürüm numarası
  await a.c.schema("ortak").rpc("kayit_yaz", { p_oyun: "deneme", p_veri: { a: 1 }, p_surum: 0 });
  assert.equal((await a.h.acilis()).surum.kayit, 1);
});

test("acilis girişsiz reddedilir; misafir kendi damgalarını alır", async () => {
  const { error } = await istemci().schema("ortak").rpc("acilis", { p_oyun: "deneme" });
  assert.ok(error && /permission denied|giris_gerekli/i.test(error.message), error?.message);
  const m = istemci();
  await m.auth.signInAnonymously();
  const r = await m.schema("ortak").rpc("acilis", { p_oyun: "deneme" });
  assert.equal(r.error, null);
  assert.equal(r.data.ben.anonim, true);
  assert.equal(r.data.surum.kayit, 0);
});

test("ben son_gorulme'yi saatte en çok bir kez yazar; yanıt aynı", async () => {
  const a = await oyuncu();
  await a.h.ben();
  await sql`update ortak.oyuncular set son_gorulme = now() - interval '10 minutes' where oyun_id = 'deneme' and kullanici_id = ${a.id}`;
  const [{ once }] = await sql`select son_gorulme as once from ortak.oyuncular where oyun_id = 'deneme' and kullanici_id = ${a.id}`;
  const b1 = await a.h.ben();
  const [{ sonra }] = await sql`select son_gorulme as sonra from ortak.oyuncular where oyun_id = 'deneme' and kullanici_id = ${a.id}`;
  assert.equal(+sonra, +once, "1 saatten yeni: yazılmaz");
  assert.equal(b1.anonim, false);
  await sql`update ortak.oyuncular set son_gorulme = now() - interval '2 hours' where oyun_id = 'deneme' and kullanici_id = ${a.id}`;
  await a.h.ben();
  const [{ son }] = await sql`select son_gorulme as son from ortak.oyuncular where oyun_id = 'deneme' and kullanici_id = ${a.id}`;
  assert.ok(Date.now() - +son < 60_000, "1 saatten eski: güncellenir");
});

test("bulut kaydı: ikinci yazma okumadan gider; başka cihaz yazınca çakışma okunup birleşir, veri kaybolmaz; açılış damgası belleği düşürür", async () => {
  const { createClient } = await import("@supabase/supabase-js");
  const { kaliciKullanici, URL: U } = await import("./yardimci.ts");
  const k = await kaliciKullanici();
  const sayac = { kayit_oku: 0, kayit_yaz: 0 };
  const cihaz = async (say: boolean) => {
    const c = createClient(U, (istemci() as unknown as { supabaseKey: string }).supabaseKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { fetch: (u: RequestInfo | URL, i?: RequestInit) => {
        const m = /rpc\/(kayit_oku|kayit_yaz)/.exec(String(u));
        if (say && m) sayac[m[1] as keyof typeof sayac]++;
        return fetch(u, i);
      } },
    });
    await c.auth.signInWithPassword({ email: k.eposta, password: k.parola });
    return hesapBaslat({ supabase: c, oyunId: "deneme", depo: bellekDepo() });
  };
  const A = await cihaz(true), B = await cihaz(false);
  const birles = (y: string[], u: string[]) => ({ kayit: [...new Set([...u, ...y])].sort() });
  const a = A.bulutKaydi<string[]>(), b = B.bulutKaydi<string[]>();

  await a.birlestir(["a1"], birles);
  assert.deepEqual(sayac, { kayit_oku: 1, kayit_yaz: 1 });
  await a.birlestir(["a1", "a2"], birles);
  assert.deepEqual(sayac, { kayit_oku: 1, kayit_yaz: 2 }, "ikinci yazma okumadan");

  await b.birlestir(["b1"], birles); // başka cihaz yazdı
  await a.birlestir(["a1", "a2", "a3"], birles); // eski sürümle dener, reddedilir, okur, birleştirir
  assert.deepEqual(sayac, { kayit_oku: 2, kayit_yaz: 4 });
  assert.deepEqual((await a.oku())!.veri, ["a1", "a2", "a3", "b1"], "iki cihazın verisi de var");

  await b.birlestir(["b2"], birles);
  const once = sayac.kayit_oku;
  await A.acilis(); // damga farklı: bellek düşer
  await a.birlestir(["a1"], birles);
  assert.equal(sayac.kayit_oku, once + 1, "açılış damgası farklı: ilk birleştirme okur");
  assert.deepEqual((await a.oku())!.veri, ["a1", "a2", "a3", "b1", "b2"]);
});

test("acilis ligli oyunda lig durumunu da döndürür", async () => {
  const a = await oyuncu();
  const r = await a.h.acilis();
  assert.ok(r.lig && "kademe" in r.lig, JSON.stringify(r));
});
