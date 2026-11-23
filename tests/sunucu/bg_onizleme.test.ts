// Göç 8320: Beat Greedy önizleme reddi. Önizlemede testçi olmayana kesif, yaris ve lig kapalı; testçiye açık; yayında
// (ve elle kapatılmamışsa) herkese açık. Elle kapatma (bayraklar.kapali) önceki gibi çalışır.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { kaliciKullanici, sql } from "./yardimci.ts";

const yedek = (await sql`select ayarlar from ortak.oyunlar where id = 'sezgi'`)[0]!.ayarlar;
after(async () => {
  await sql`update ortak.oyunlar set ayarlar = ${sql.json(yedek)} where id = 'sezgi'`;
  await sql.end();
});

const kapali = async (bolum: string, k: string) =>
  (await sql`select sezgi.bolum_kapali(${bolum}, ${k}::uuid) as v`)[0]!.v as boolean;
const ayarla = (ek: unknown) => sql`update ortak.oyunlar set ayarlar = (ayarlar - 'yayin' - 'bayraklar') || ${sql.json(ek)} where id = 'sezgi'`;

test("8320 BG önizleme: testçi dışına kesif/yaris/lig kapalı, testçiye açık; yayında açık; elle kapatma sürer", async () => {
  const a = await kaliciKullanici(), t = await kaliciKullanici();
  await sql`insert into ortak.testciler (kullanici_id) values (${t.id})`;

  await ayarla({ bayraklar: {} });
  for (const b of ["kesif", "yaris", "lig"]) assert.equal(await kapali(b, a.id), false, `yayında ${b} açık`);

  await ayarla({ yayin: "onizleme", bayraklar: {} });
  for (const b of ["kesif", "yaris", "lig"]) {
    assert.equal(await kapali(b, a.id), true, `önizlemede testçi dışına ${b} kapalı`);
    assert.equal(await kapali(b, t.id), false, `testçiye ${b} açık`);
  }

  await ayarla({ bayraklar: { kapali: ["yaris"] } });
  assert.equal(await kapali("yaris", a.id), true, "elle kapatma");
  assert.equal(await kapali("kesif", a.id), false);
  await sql`delete from ortak.testciler where kullanici_id = ${t.id}`;
});
