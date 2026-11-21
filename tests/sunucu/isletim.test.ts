// Göç 20261120006800 (işletim): durum özeti, yönetim kaydı, açılmış bulmaca koruması, bayraklar, ödül işlerinin saati ve
// tekrarlanabilirliği (iki kez çalışan iş çift ödül üretmez).
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { hesapBaslat } from "../../src/hesap/index.ts";
import { bellekDepo } from "../../src/kayit/index.ts";
import { istemci, kaliciGir, sql } from "./yardimci.ts";

after(() => sql.end());

const gun = (fark: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + fark * 864e5));

test("isletim_durumu: işler, içerik, bekleyen, son 24 saat; istemciye kapalı", async () => {
  const [{ v }] = await sql`select ortak.isletim_durumu() as v`;
  assert.deepEqual(Object.keys(v).sort(), ["bekleyen", "boyut", "bugun", "icerik", "isler", "son_24s", "zaman"]);
  assert.ok(v.isler.some((i: { ad: string }) => i.ad === "ortak-lig-kapat"));
  assert.ok("halka_gunluk_kalan_gun" in v.icerik);
  for (const rol of ["anon", "authenticated"]) {
    const [{ yetki }] = await sql`select has_function_privilege(${rol}, 'ortak.isletim_durumu()', 'execute') as yetki`;
    assert.equal(yetki, false, rol);
  }
});

test("haftalık ödül işleri gece yarısında değil (03:05 ve 03:15 İstanbul)", async () => {
  const r = await sql`select jobname, schedule from cron.job where jobname in ('halka-turnuva-odul', 'sticky-haftalik-odul') order by 1`;
  assert.deepEqual(r.map((x) => [x.jobname, x.schedule]), [["halka-turnuva-odul", "15 0 * * 1"], ["sticky-haftalik-odul", "5 0 * * 1"]]);
});

test("yönetim kaydı: değişen satır kaydedilir, aynı içerik yeniden yazılınca kayıt yok", async () => {
  const once = Number((await sql`select count(*) from ortak.yonetim_kaydi where tablo = 'ortak.oyunlar'`)[0]!.count);
  await sql`update ortak.oyunlar set ayarlar = ayarlar || '{"deneme_kayit": 1}' where id = 'deneme'`;
  await sql`update ortak.oyunlar set ayarlar = ayarlar where id = 'deneme'`; // aynı içerik
  const r = await sql`select islem, anahtar, degisen, rol from ortak.yonetim_kaydi where tablo = 'ortak.oyunlar' order by id desc limit 1`;
  assert.equal(Number((await sql`select count(*) from ortak.yonetim_kaydi where tablo = 'ortak.oyunlar'`)[0]!.count), once + 1);
  assert.deepEqual({ ...r[0] }, { islem: "UPDATE", anahtar: "deneme", degisen: ["ayarlar"], rol: "postgres" });
  await sql`update ortak.oyunlar set ayarlar = ayarlar - 'deneme_kayit' where id = 'deneme'`;
});

test("açılmış bulmaca sessizce değiştirilemez; bilinçli düzeltme kaydedilir; gelecek gün serbest", async () => {
  const dun = gun(-1), yarin = gun(5);
  await sql`delete from halka.gunluk_bulmacalar where tarih in (${dun}, ${yarin})`.catch(() => {});
  await sql.begin(async (t) => {
    await t`set local halka.duzeltme = 'evet'`;
    await t`delete from halka.gunluk_bulmacalar where tarih in (${dun}, ${yarin})`;
  });
  await sql`insert into halka.gunluk_bulmacalar (tarih, halkalar, cevaplar) values (${dun}, '[["a"]]', '{a}'), (${yarin}, '[["a"]]', '{a}')`;
  await assert.rejects(sql`update halka.gunluk_bulmacalar set cevaplar = '{b}' where tarih = ${dun}`, /acilmis_bulmaca_degisemez/);
  await assert.rejects(sql`delete from halka.gunluk_bulmacalar where tarih = ${dun}`, /acilmis_bulmaca_degisemez/);
  await sql`update halka.gunluk_bulmacalar set cevaplar = '{a}' where tarih = ${dun}`; // aynı içerik: serbest
  await sql`update halka.gunluk_bulmacalar set cevaplar = '{b}' where tarih = ${yarin}`; // gelecek gün: serbest
  await sql.begin(async (t) => {
    await t`set local halka.duzeltme = 'evet'`;
    await t`update halka.gunluk_bulmacalar set cevaplar = '{c}' where tarih = ${dun}`;
  });
  const [k] = await sql`select islem, degisen from ortak.yonetim_kaydi where tablo = 'halka.gunluk_bulmacalar' and anahtar = ${dun} order by id desc limit 1`;
  assert.deepEqual({ ...k }, { islem: "UPDATE", degisen: ["cevaplar"] });
  await sql.begin(async (t) => {
    await t`set local halka.duzeltme = 'evet'`;
    await t`delete from halka.gunluk_bulmacalar where tarih in (${dun}, ${yarin})`;
  });
});

test("açılmış turnuva bulmacası da korunur; başlamamış turnuva serbest", async () => {
  const k1 = `usta-${gun(-1)}`, k2 = `usta-${gun(6)}`;
  const temizle = () => sql.begin(async (t) => {
    await t`set local halka.duzeltme = 'evet'`;
    await t`delete from halka.turnuva_bulmacalar where kimlik in (${k1}, ${k2})`;
  });
  await temizle();
  await sql`insert into halka.turnuva_bulmacalar (kimlik, basla, bitir, halkalar, cevaplar) values
    (${k1}, ${gun(-1)}, ${gun(0)}, '[["a"]]', '{a}'), (${k2}, ${gun(6)}, ${gun(7)}, '[["a"]]', '{a}')`;
  await assert.rejects(sql`update halka.turnuva_bulmacalar set cevaplar = '{b}' where kimlik = ${k1}`, /acilmis_bulmaca_degisemez/);
  await sql`update halka.turnuva_bulmacalar set cevaplar = '{b}' where kimlik = ${k2}`;
  await temizle();
});

test("acilis sunucu kontrollü bayrakları döndürür", async () => {
  await sql`update ortak.oyunlar set ayarlar = ayarlar || '{"bayraklar": {"kapali": ["turnuva"], "asgari_surum": "1.0.3"}}' where id = 'deneme'`;
  const c = istemci();
  const h = hesapBaslat({ supabase: c, oyunId: "deneme", depo: bellekDepo() });
  await kaliciGir(h);
  const r = await h.acilis();
  assert.deepEqual((r as unknown as { bayraklar: unknown }).bayraklar, { kapali: ["turnuva"], asgari_surum: "1.0.3" });
  await sql`update ortak.oyunlar set ayarlar = ayarlar - 'bayraklar' where id = 'deneme'`;
});

test("ödül işi iki kez çalışınca çift ödül yok (turnuva ve Sticky haftalık)", async () => {
  const say = async () => Number((await sql`select count(*) from ortak.oduller`)[0]!.count);
  await sql`select halka.turnuva_odul_ver()`;
  await sql`select sticky.haftalik_odul()`;
  const a = await say();
  await sql`select halka.turnuva_odul_ver()`;
  await sql`select sticky.haftalik_odul()`;
  assert.equal(await say(), a);
});

test("7500 panel_durumu: yanlış anahtar null, doğru anahtar durum + son yedek; tablolar istemciye kapalı", async () => {
  await sql`delete from ortak.panel_ayar`;
  await sql`insert into ortak.panel_ayar (anahtar_ozet) values (extensions.digest('test-anahtar', 'sha256'))`;
  const anon = istemci().schema("ortak");
  assert.equal((await anon.rpc("panel_durumu", { p_anahtar: "yanlis" })).data, null, "yanlış anahtar");
  assert.equal((await anon.rpc("yedek_kaydet", { p_anahtar: "yanlis", p_proje: "canli", p_basarili: true, p_boyut: 1, p_not: null })).error?.message.includes("anahtar"), true, "yanlış anahtarla yedek yazılmaz");
  assert.equal((await anon.rpc("yedek_kaydet", { p_anahtar: "test-anahtar", p_proje: "canli", p_basarili: true, p_boyut: 123, p_not: "deneme" })).error, null);
  const { data: d } = await anon.rpc("panel_durumu", { p_anahtar: "test-anahtar" });
  assert.ok(d && Array.isArray(d.isler), "isletim alanları");
  assert.equal(d.son_yedek.basarili, true);
  assert.equal(typeof d.auth_kullanici, "number");
  for (const t of ["panel_ayar", "yedek_kayitlari"]) assert.ok((await anon.from(t).select("*").limit(1)).error, `${t} istemciye kapalı`);
  await sql`delete from ortak.panel_ayar`;
});
