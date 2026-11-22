// Göç 8280: yayın öncesi önizleme. Önizlemedeki oyunda test listesi dışındakine günlük, lig, etkinlik, sıralama ve düello
// kapalı (mevcut kapali listesi korunur); testçiye her şey açık. Yayında ('acik') bayraklar olduğu gibi. Liste istemciye kapalı.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { hesapBaslat } from "../../src/hesap/index.ts";
import { bellekDepo } from "../../src/kayit/index.ts";
import { istemci, kaliciGir, sql } from "./yardimci.ts";

const OYUN = "deneme";
const ayarYedek = (await sql`select ayarlar from ortak.oyunlar where id = ${OYUN}`)[0]!.ayarlar;
after(async () => {
  await sql`update ortak.oyunlar set ayarlar = ${sql.json(ayarYedek)} where id = ${OYUN}`;
  await sql.end();
});

async function oyuncu() {
  const c = istemci();
  const h = hesapBaslat({ supabase: c, oyunId: OYUN, depo: bellekDepo() });
  const id = await kaliciGir(h);
  return { c, h, id };
}

const ayarla = (yayin: string | null, bayraklar: unknown) =>
  sql`update ortak.oyunlar set ayarlar = (ayarlar - 'yayin' - 'bayraklar')
        || ${sql.json(yayin ? { yayin, bayraklar } : { bayraklar })} where id = ${OYUN}`;

test("8280 önizleme: halka kapalı (eski kapali korunur), testçi açık; yayında bayraklar aynen; liste istemciye kapalı", async () => {
  const a = await oyuncu(), t = await oyuncu();
  await sql`insert into ortak.testciler (kullanici_id, aciklama) values (${t.id}, 'test')`;

  await ayarla(null, { kapali: ["turnuva"], duyuru: "x" });
  assert.deepEqual((await a.h.acilis()).bayraklar, { kapali: ["turnuva"], duyuru: "x" }, "yayin yoksa açık sayılır");

  await ayarla("onizleme", { kapali: ["turnuva"], duyuru: "x" });
  const ab = (await a.h.acilis()).bayraklar;
  assert.equal(ab.onizleme, true);
  assert.equal(ab.testci, undefined);
  assert.deepEqual([...ab.kapali!].sort(), ["duello", "etkinlik", "gunluk", "lig", "siralama", "turnuva"]);
  assert.equal(ab.duyuru, "x");

  const tb = (await t.h.acilis()).bayraklar;
  assert.equal(tb.onizleme, true);
  assert.equal(tb.testci, true);
  assert.equal(tb.lig_acik, true);
  assert.deepEqual(tb.kapali, ["turnuva"], "testçiye yalnız elle kapatılanlar kapalı");

  const [{ b }] = await sql`select ortak.etkin_bayraklar(${OYUN}, ${a.id}::uuid) as b`;
  assert.ok(b.kapali.includes("gunluk"), "sunucu yardımcısının sorduğu işlev aynı sonucu verir");

  await ayarla("acik", { kapali: [] });
  assert.deepEqual((await a.h.acilis()).bayraklar, { kapali: [] });
  assert.deepEqual((await t.h.acilis()).bayraklar, { kapali: [], testci: true }, "8300: yayından sonra da testçi");

  // 8310: oturumsuz ziyaretçi de halka açık bayrakları alır (önizlemede kilitli görünüm)
  await ayarla("onizleme", { kapali: ["turnuva"] });
  const oturumsuz = hesapBaslat({ supabase: istemci(), oyunId: OYUN, depo: bellekDepo() });
  const ob = await oturumsuz.oyunBayraklari();
  assert.equal(ob.onizleme, true);
  assert.ok(ob.kapali!.includes("gunluk") && ob.kapali!.includes("turnuva"));
  assert.equal(ob.testci, undefined);
  assert.equal((await t.h.oyunBayraklari()).testci, undefined, "testçi bilgisi yalnız acilis'te");

  // 8290: yayın tarihi herkese döner (önizlemede de)
  await sql`update ortak.oyunlar set ayarlar = ayarlar || '{"yayin": "onizleme", "yayin_tarihi": "2027-01-15"}'::jsonb where id = ${OYUN}`;
  assert.equal((await a.h.acilis()).bayraklar.yayin_tarihi, "2027-01-15");
  assert.equal((await t.h.acilis()).bayraklar.yayin_tarihi, "2027-01-15");

  assert.ok((await a.c.schema("ortak").from("testciler").select("*")).error, "liste okunamaz");
  assert.ok((await a.c.schema("ortak").rpc("etkin_bayraklar", { p_oyun: OYUN, p_kullanici: a.id })).error, "işlev istemciye kapalı");
  await sql`delete from ortak.testciler where kullanici_id = ${t.id}`;
});
