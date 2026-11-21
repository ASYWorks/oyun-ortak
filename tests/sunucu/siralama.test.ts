import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import { bellekDepo } from "../../src/kayit/index.ts";
import { hesapBaslat } from "../../src/hesap/index.ts";
import { siralamaBaslat } from "../../src/siralama/index.ts";
import { bugun, fonksiyon, istemci, kaliciGir, kaliciKullanici, oyunuTemizle, sql, adVer } from "./yardimci.ts";

before(() => oyunuTemizle());
after(() => sql.end());

const oyuncu = async () => {
  const c = istemci();
  const h = hesapBaslat({ supabase: c, oyunId: "deneme", depo: bellekDepo() });
  const id = await kaliciGir(h); // günlük sıralama yalnız hesapla (15 Kasım 2026)
  await adVer(id); // ve seçilmiş adla
  return { c, h, id };
};

/** SQL ile sahte oyuncu (auth.users satırı) ve doğrudan skor. */
async function sahteSkor(donem: string, puan: number, ikincil = 1) {
  const [{ id }] = await sql`insert into auth.users (id, aud, role, is_anonymous) values (gen_random_uuid(), 'authenticated', 'authenticated', false) returning id`;
  await adVer(id);
  await sql`select ortak.skor_yaz('deneme', ${id}, 'gunluk', ${donem}, ${puan}, gen_random_uuid(), ${ikincil})`;
  return id as string;
}

const gunluk = (kayit: number[], ek: Record<string, unknown> = {}) => ({
  islem: "gunluk", gun: bugun(), kayit, kuralSurumu: 1, runId: crypto.randomUUID(), ...ek,
});

test("günlük gönderim: puanı sunucu hesaplar; aynı runId tek skor; ikinci gönderim prova", async () => {
  const { c } = await oyuncu();
  const g = gunluk([9, 9, 1]);
  const r1 = await fonksiyon(c, "dogrula-deneme", { ...g, puan: 999 });
  assert.equal(r1.durum, 200);
  assert.equal(r1.veri.durum, "yeni");
  assert.equal(r1.veri.puan, 19);
  const r2 = await fonksiyon(c, "dogrula-deneme", g);
  assert.equal(r2.veri.durum, "tekrar");
  const r3 = await fonksiyon(c, "dogrula-deneme", gunluk([1]));
  assert.equal(r3.veri.durum, "prova");
});

test("ret: gelecek gün, sürüm, biçim, oturum, gövde", async () => {
  const { c } = await oyuncu();
  const yarin = new Date(Date.now() + 86_400_000).toLocaleDateString("en-CA", { timeZone: "Europe/Istanbul" });
  const durum = async (g: unknown, cc: typeof c | null = c) => (await fonksiyon(cc, "dogrula-deneme", g)).durum;
  assert.equal(await durum(gunluk([1], { gun: yarin })), 409);
  assert.equal(await durum(gunluk([1], { gun: "2020-01-01" })), 409);
  assert.equal(await durum(gunluk([1], { kuralSurumu: 0 })), 426);
  assert.equal(await durum(gunluk([10])), 400);
  assert.equal(await durum(gunluk([])), 400);
  assert.equal(await durum(gunluk([1], { runId: "x" })), 400);
  assert.equal(await durum("{bozuk"), 400);
  assert.equal(await durum({ islem: "gunluk", gun: bugun(), kayit: [1], kuralSurumu: 1, runId: crypto.randomUUID(), dolgu: "x".repeat(70_000) }), 413);
  assert.equal(await durum(gunluk([1]), null), 401);
});

test("durum tutan deneme: sıra, yeniden gönderim, eş zamanlı yarış, bitiş", async () => {
  const { c } = await oyuncu();
  const olay = (sira: number, o: number) => fonksiyon(c, "dogrula-deneme", { islem: "olay", gun: bugun(), sira, olay: o });
  assert.equal((await olay(0, 4)).veri.durum, "devam");
  assert.equal((await olay(0, 4)).veri.durum, "tekrar"); // aynı olay ikinci kez: tek sayılır
  assert.equal((await olay(5, 1)).durum, 409);
  const [a, b] = await Promise.all([olay(1, 7), olay(1, 8)]);
  assert.deepEqual([a.durum, b.durum].sort(), [200, 409]);
  const son = await olay(2, -1);
  assert.equal(son.veri.durum, "yeni");
  assert.ok(son.veri.puan === 11 || son.veri.puan === 12);
  assert.equal((await olay(3, 1)).durum, 409); // bitmiş deneme yeniden açılmaz
});

test("istek sınırı: kullanıcı başına dakikada 30", async () => {
  const { c } = await oyuncu();
  const durumlar: number[] = [];
  for (let i = 0; i < 31; i++) durumlar.push((await fonksiyon(c, "dogrula-deneme", { islem: "yok", gun: bugun() })).durum);
  assert.equal(durumlar.filter((d) => d === 429).length, 1);
  assert.equal(durumlar.at(-1), 429);
});

test("gönderim kuyruğu: ağ yokken bekler, ağ gelince gider", async () => {
  const depo = bellekDepo();
  const olu = createClient("http://127.0.0.1:9", "x", { auth: { persistSession: false } });
  const s1 = siralamaBaslat({ supabase: olu, oyunId: "deneme", depo });
  const r = await s1.gonder(gunluk([3, 3]));
  assert.equal(r.bekliyor, true);
  assert.equal(await s1.bekleyenSayisi(), 1);

  const { c } = await oyuncu();
  const s2 = siralamaBaslat({ supabase: c, oyunId: "deneme", depo });
  const sonuc = await s2.bosalt();
  assert.equal(sonuc[0]!.durum, 200);
  assert.equal((sonuc[0]!.veri as { puan: number }).puan, 6);
  assert.equal(await s2.bekleyenSayisi(), 0);

  // kalıcı ret kuyruktan düşer
  const r2 = await s2.gonder(gunluk([1], { kuralSurumu: 99 }));
  assert.deepEqual([r2.durum, r2.bekliyor], [426, false]);
  assert.equal(await s2.bekleyenSayisi(), 0);
});

test("tablo: eşit puana aynı sıra, ilk N + çevre, 50 altında yüzdelik yok", async () => {
  const donem = "2026-01-05";
  await sahteSkor(donem, 50);
  await sahteSkor(donem, 50);
  for (let i = 0; i < 6; i++) await sahteSkor(donem, 40 - i);
  const { c, id } = await oyuncu();
  await sql`select ortak.skor_yaz('deneme', ${id}, 'gunluk', ${donem}, 1, gen_random_uuid(), 1)`;
  for (let i = 0; i < 3; i++) await sahteSkor(donem, 0);

  const s = siralamaBaslat({ supabase: c, oyunId: "deneme", depo: bellekDepo() });
  const t = await s.tablo("gunluk", donem, { ilk: 2, cevre: 1 });
  assert.equal(t.toplam, 12);
  assert.deepEqual(t.satirlar.slice(0, 2).map((x) => x.sira), [1, 1]);
  assert.deepEqual(t.satirlar.map((x) => x.puan), [50, 50, 35, 1, 0]);
  assert.deepEqual(t.ben, { sira: 9, ust_yuzde: null });
  assert.equal(t.satirlar.filter((x) => x.ben).length, 1);
  assert.ok(t.satirlar.every((x) => !("kullanici_id" in x)));

  for (let i = 0; i < 40; i++) await sahteSkor(donem, 100);
  const t2 = await s.tablo("gunluk", donem);
  assert.equal(t2.ben?.ust_yuzde, Math.ceil((100 * 49) / 52));

  // GC-3: servis rolünün okuduğu sıra tablodakiyle aynı; skoru olmayana null; istemci çağıramaz
  const [{ r }] = await sql`select ortak.kullanici_sirasi('deneme', 'gunluk', ${donem}, ${id}) as r`;
  assert.deepEqual(r, { sira: 49, toplam: 52, ust_yuzde: Math.ceil((100 * 49) / 52) });
  const [{ r: yok }] = await sql`select ortak.kullanici_sirasi('deneme', 'gunluk', '2026-01-06', ${id}) as r`;
  assert.equal(yok, null);
  assert.ok((await c.schema("ortak").rpc("kullanici_sirasi", { p_oyun: "deneme", p_tur: "gunluk", p_donem: donem, p_kullanici: id })).error);
});

test("kurulum başına günde bir hesap günlük sıralamaya girer (aynı uygulama/tarayıcıdan ikinci hesap 'cihaz')", async () => {
  const [a, b] = [await kaliciKullanici(), await kaliciKullanici()];
  await adVer(a.id); await adVer(b.id);
  const cihaz = crypto.randomUUID();
  const yaz = async (kullanici: string, c: string | null, tur = "gunluk") =>
    ((await sql`select ortak.skor_yaz('deneme', ${kullanici}, ${tur}, ${bugun()}, 10, gen_random_uuid(), p_cihaz => ${c}) as r`)[0]!.r as { durum: string }).durum;
  assert.equal(await yaz(a.id, cihaz), "yeni");
  assert.equal(await yaz(b.id, cihaz), "cihaz"); // aynı kurulumdan ikinci hesap
  assert.equal(await yaz(a.id, cihaz), "prova"); // aynı hesap: eski kural (günün ilk skoru)
  assert.equal((await sql`select count(*)::int as n from ortak.skorlar where kullanici_id = ${b.id}`)[0]!.n, 0);
  assert.equal(await yaz(b.id, crypto.randomUUID()), "yeni"); // başka kurulumdan girer
  const c = await kaliciKullanici();
  await adVer(c.id);
  assert.equal(await yaz(c.id, null), "yeni"); // kimlik yok (eski istemci): denetim yok
  assert.equal(await yaz(c.id, cihaz, "etkinlik"), "yeni"); // günlük dışı etkilenmez
  // Beat Greedy yolu
  const t = async (kullanici: string) =>
    ((await sql`select ortak.gun_toplami_yaz('deneme', ${kullanici}, ${bugun()}, 5, p_cihaz => ${cihaz}) as r`)[0]!.r as { durum?: string }).durum;
  assert.equal(await t(c.id), "cihaz");
});

test("günlük, lig ve etkinlik yalnız hesapla: misafirin skoru yazılmaz ('misafir')", async () => {
  const [{ id }] = await sql`insert into auth.users (id, aud, role, is_anonymous) values (gen_random_uuid(), 'authenticated', 'authenticated', true) returning id`;
  for (const tur of ["gunluk", "etkinlik"]) {
    const r = (await sql`select ortak.skor_yaz('deneme', ${id}, ${tur}, ${bugun()}, 10, gen_random_uuid()) as r`)[0]!.r as { durum: string };
    assert.equal(r.durum, "misafir", tur);
  }
  const g = (await sql`select ortak.gun_toplami_yaz('deneme', ${id}, ${bugun()}, 5) as r`)[0]!.r as { durum?: string };
  assert.equal(g.durum, "misafir");
  assert.equal((await sql`select count(*)::int as n from ortak.skorlar where kullanici_id = ${id}`)[0]!.n, 0);
  assert.equal((await sql`select count(*)::int as n from ortak.lig_uyeleri where kullanici_id = ${id}`)[0]!.n, 0);
});

test("ad seçmeden sıralama yok: otomatik adlı hesabın skoru yazılmaz ('ad_gerekli'), ad seçince yazılır", async () => {
  const k = await kaliciKullanici();
  await sql`insert into ortak.oyuncular (oyun_id, kullanici_id, ad, ad_anahtari, ad_otomatik) values ('deneme', ${k.id}, '#ABCDE', 'abcde', true) on conflict do nothing`;
  const run = crypto.randomUUID();
  const yaz = async () => ((await sql`select ortak.skor_yaz('deneme', ${k.id}, 'gunluk', ${bugun()}, 10, ${run}) as r`)[0]!.r as { durum: string }).durum;
  assert.equal(await yaz(), "ad_gerekli");
  const g = (await sql`select ortak.gun_toplami_yaz('deneme', ${k.id}, ${bugun()}, 5) as r`)[0]!.r as { durum?: string };
  assert.equal(g.durum, "ad_gerekli");
  assert.equal((await sql`select count(*)::int as n from ortak.skorlar where kullanici_id = ${k.id}`)[0]!.n, 0);
  await adVer(k.id);
  assert.equal(await yaz(), "yeni"); // aynı runId yeniden gönderilince yazılır
});

test("PU-3 kalibrasyon: dönem başına süre dağılımı ve ipucu türleri; bayraklı skor dışarıda; yalnız servis rolü", async () => {
  const oyun = "deneme", donem = `kal-${crypto.randomUUID().slice(0, 8)}`;
  const ekle = async (sure: number, ipuclari: string[], bayrak: string[] = []) => {
    const k = await kaliciKullanici();
    await sql`insert into ortak.skorlar (oyun_id, kullanici_id, tur, donem, puan, run_id, ayrinti, bayraklar)
      values (${oyun}, ${k.id}, 'etkinlik', ${donem}, 1, gen_random_uuid(),
              ${sql.json({ puan_surumu: 1, sure, ipuclari, zorluk: 30, hedef_sure: 25, puan_ham: 4 })}, ${bayrak})`;
  };
  await ekle(10, []); await ekle(20, ["kilit"]); await ekle(30, ["tema", "kilit"]); await ekle(1, [], ["hizli"]);
  const [r] = await sql`select * from ortak.kalibrasyon(${oyun}, now() - interval '1 hour', now() + interval '1 hour') where donem = ${donem}`;
  assert.equal(Number(r!.oyuncu), 3);
  assert.equal(Number(r!.sure_p50), 20);
  assert.equal(Number(r!.ipucu_orani), 0.667);
  assert.deepEqual(r!.ipucu_turleri, { kilit: 2, tema: 1 });
  await sql`delete from ortak.skorlar where donem = ${donem}`;
  const yetki = await sql`select has_function_privilege('authenticated', 'ortak.kalibrasyon(text, timestamptz, timestamptz)', 'execute') as a`;
  assert.equal(yetki[0]!.a, false);
});

test("nabız: süre yalnız ekrandayken birikir; duraklama sayılmaz; sık nabız şişiremez; bitmiş denemede durur", async () => {
  const c = istemci();
  const h = hesapBaslat({ supabase: c, oyunId: "deneme", depo: bellekDepo() });
  const uid = await kaliciGir(h);
  const s = siralamaBaslat({ supabase: c, oyunId: "deneme", depo: bellekDepo() });
  const anahtar = `nabiz:${crypto.randomUUID()}`;
  const geri = (ms: number) => sql`update ortak.denemeler set son_nabiz = son_nabiz - ${ms + " milliseconds"}::interval where kullanici_id = ${uid} and anahtar = ${anahtar}`;
  assert.equal(await s.nabiz(anahtar), 0, "ilk nabız denemeyi açar");
  await geri(8000);
  assert.ok(Math.abs((await s.nabiz(anahtar)) - 8000) < 500, "8 sn eklendi");
  await geri(10 * 60_000); // 10 dk duraklama
  const t = await s.nabiz(anahtar);
  assert.ok(Math.abs(t - 8000) < 1000, `90 sn'den uzun boşluk süreye eklenmez, duraklatma sayılır: ${t}`);
  const [b] = await sql`select durak_ms from ortak.denemeler where kullanici_id = ${uid} and anahtar = ${anahtar}`;
  assert.ok(Math.abs(Number(b!.durak_ms) - 600_000) < 1000, `örtük duraklatma: ${b!.durak_ms}`);
  await geri(60_000);
  assert.ok(Math.abs((await s.nabiz(anahtar)) - t - 60_000) < 1000, "90 sn'ye kadar boşluk tam sayılır (B1)");
  const t2 = await s.nabiz(anahtar);
  for (let i = 0; i < 5; i++) await s.nabiz(anahtar);
  assert.ok((await s.nabiz(anahtar)) - t2 < 1000, "sık nabız süre eklemez");
  const [d] = await sql`select aktif_ms, son_nabiz from ortak.denemeler where kullanici_id = ${uid} and anahtar = ${anahtar}`;
  const { aktifSureMs } = await import("../../sunucu/sure.ts");
  assert.ok(Math.abs(aktifSureMs({ aktif_ms: Number(d!.aktif_ms), son_nabiz: d!.son_nabiz.toISOString() }, new Date(d!.son_nabiz.getTime() + 60_000))! - (Number(d!.aktif_ms) + 60_000)) < 1);
  assert.equal(aktifSureMs({ aktif_ms: 0, son_nabiz: null }, new Date()), null);
  await sql`update ortak.denemeler set bitti = true where kullanici_id = ${uid} and anahtar = ${anahtar}`;
  await geri(5000);
  assert.equal(await s.nabiz(anahtar), Number(d!.aktif_ms), "bitince süre artmaz");
  const m = istemci();
  assert.match((await m.schema("ortak").rpc("nabiz", { p_oyun: "deneme", p_anahtar: anahtar })).error?.message ?? "", /permission denied|JWT|yetki/i);
});

test("nabız durdur: duraklatma süreye eklenmez; teslimde durdu yok sayılır", async () => {
  const c = istemci();
  const h = hesapBaslat({ supabase: c, oyunId: "deneme", depo: bellekDepo() });
  const uid = await kaliciGir(h);
  const s = siralamaBaslat({ supabase: c, oyunId: "deneme", depo: bellekDepo() });
  const anahtar = `durdur:${crypto.randomUUID()}`;
  const geri = (ms: number) => sql`update ortak.denemeler set son_nabiz = son_nabiz - ${ms + " milliseconds"}::interval where kullanici_id = ${uid} and anahtar = ${anahtar}`;
  await s.nabiz(anahtar);
  await geri(9000);
  const durdu = await s.nabiz(anahtar, true);
  assert.ok(Math.abs(durdu - 9000) < 600, "durdur nabzı o ana kadarki süreyi sayar");
  await geri(5 * 60_000); // 5 dk duraklama
  const devam = await s.nabiz(anahtar);
  assert.ok(Math.abs(devam - durdu) < 50, `duraklama eklenmez: ${devam - durdu}`);
  await s.nabiz(anahtar, true);
  const [d] = await sql`select aktif_ms, son_nabiz, durdu from ortak.denemeler where kullanici_id = ${uid} and anahtar = ${anahtar}`;
  const { aktifSureMs } = await import("../../sunucu/sure.ts");
  // teslimde durdu yok sayılır: son aralık tam sayılır
  const simdi = new Date(d!.son_nabiz.getTime() + 600_000);
  assert.equal(aktifSureMs({ aktif_ms: Number(d!.aktif_ms), son_nabiz: d!.son_nabiz.toISOString(), durdu: d!.durdu }, simdi), Number(d!.aktif_ms) + 600_000);
  // 5 dk duraklama durak_ms'e yazıldı; etkin süreyi (≈9 sn) ve 2 dk'yı aşıyor → bayrak
  const [e] = await sql`select durak_ms from ortak.denemeler where kullanici_id = ${uid} and anahtar = ${anahtar}`;
  assert.ok(Math.abs(Number(e!.durak_ms) - 300_000) < 1000, `durak_ms: ${e!.durak_ms}`);
  const { nabizBoslugu } = await import("../../sunucu/sure.ts");
  assert.equal(nabizBoslugu({ durak_ms: e!.durak_ms }, durdu), true);
  assert.equal(nabizBoslugu({ durak_ms: 100_000 }, 10_000), false, "2 dk altı duraklama bayraksız");
});
