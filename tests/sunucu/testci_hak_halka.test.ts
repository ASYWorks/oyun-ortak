// Göç 8330: testçi her hakkı taşıyor sayılır (korumalı içerik). Göç 8340: Halka önizlemede günlük kontrolü testçi olmayana
// 'kapali', testçiye açık; arşiv dizini testçi olmayana boş.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { hesapBaslat } from "../../src/hesap/index.ts";
import { bellekDepo } from "../../src/kayit/index.ts";
import { bugun, istemci, kaliciGir, sql } from "./yardimci.ts";

const yedek = (await sql`select ayarlar from ortak.oyunlar where id = 'halka'`)[0]!.ayarlar;
after(async () => {
  await sql`update ortak.oyunlar set ayarlar = ${sql.json(yedek)} where id = 'halka'`;
  await sql.end();
});

async function oyuncu() {
  const c = istemci();
  const h = hesapBaslat({ supabase: c, oyunId: "halka", depo: bellekDepo() });
  const id = await kaliciGir(h);
  return { c, id };
}

test("8330 hakki_var: testçi her hakkı taşır, başkası taşımaz", async () => {
  const a = await oyuncu(), t = await oyuncu();
  await sql`insert into ortak.testciler (kullanici_id) values (${t.id})`;
  const hak = async (c: typeof a.c) => (await c.schema("ortak").rpc("hakki_var", { p_oyun: "halka", p_hak: "paket_tam" })).data;
  assert.equal(await hak(a.c), false);
  assert.equal(await hak(t.c), true);
  await sql`delete from ortak.testciler where kullanici_id = ${t.id}`;
});

test("8340 Halka önizleme: günlük kontrolü testçi dışına kapalı, testçiye açık; dizin testçi dışına boş", async () => {
  const a = await oyuncu(), t = await oyuncu();
  await sql`insert into ortak.testciler (kullanici_id) values (${t.id})`;
  await sql`update ortak.oyunlar set ayarlar = ayarlar || '{"yayin": "onizleme"}'::jsonb where id = 'halka'`;
  const kontrol = (c: typeof a.c) => c.rpc("halka_gunluk_kontrol", { p_tarih: bugun(), p_rot: [], p_flip: [] });
  assert.match(String((await kontrol(a.c)).error?.message), /kapali/);
  assert.doesNotMatch(String((await kontrol(t.c)).error?.message ?? ""), /kapali/, "testçi kapali almaz");
  assert.deepEqual((await a.c.rpc("halka_gunluk_dizin")).data, []);
  await sql`update ortak.oyunlar set ayarlar = ayarlar || '{"yayin": "acik"}'::jsonb where id = 'halka'`;
  assert.doesNotMatch(String((await kontrol(a.c)).error?.message ?? ""), /kapali/, "yayında açık");
  await sql`delete from ortak.testciler where kullanici_id = ${t.id}`;
});

test("8370 Halka kademeli: yayında turnuva kapalı → Usta kapalı, tema açık; gunluk kapalı → arşiv boş; testçiye hepsi açık", async () => {
  const a = await oyuncu(), t = await oyuncu();
  await sql`insert into ortak.testciler (kullanici_id) values (${t.id})`;
  const tk = (c: typeof a.c, kimlik: string) => c.rpc("halka_turnuva_kontrol", { p_kimlik: kimlik, p_rot: [], p_flip: [] });
  const kapaliMi = async (c: typeof a.c, kimlik: string) => /kapali/.test(String((await tk(c, kimlik)).error?.message ?? ""));
  const ayarla = (kapali: string[]) =>
    sql`update ortak.oyunlar set ayarlar = (ayarlar - 'yayin') || ${sql.json({ yayin: "acik", bayraklar: { ...(yedek.bayraklar ?? {}), kapali } })} where id = 'halka'`;

  await ayarla(["turnuva"]);
  assert.equal(await kapaliMi(a.c, "usta-2026-11-30"), true, "Usta turnuva bayrağına bağlı");
  assert.equal(await kapaliMi(a.c, "hafta-2026-11-30-1"), false, "tema etkinlik bayrağına bağlı");
  assert.equal(await kapaliMi(t.c, "usta-2026-11-30"), false, "testçiye açık (8360)");

  await ayarla(["etkinlik"]);
  assert.equal(await kapaliMi(a.c, "usta-2026-11-30"), false);
  assert.equal(await kapaliMi(a.c, "hafta-2026-11-30-1"), true);

  await ayarla(["gunluk"]);
  assert.deepEqual((await a.c.rpc("halka_gunluk_dizin")).data, [], "yayında da günlük kapalıysa arşiv boş");
  assert.equal((await a.c.rpc("halka_gunluk_cevap", { p_tarih: bugun() })).data, null);
  await sql`delete from ortak.testciler where kullanici_id = ${t.id}`;
});
