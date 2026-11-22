// Göç 8180 (Mahalle Dönüşümü): oyun satırı, gizli günlük tablo yalnız servis rolüne, açılmış gün koruması, yükleme kuralı.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { istemci, sql, yonetici , gunlukKoru } from "./yardimci.ts";

let geriKoy: (() => Promise<void>) | undefined;
after(async () => { await geriKoy?.(); await sql.end(); });

const gun = (fark: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + fark * 864e5));
const bes = (k: string) => Array.from({ length: 5 }, (_, i) => ({ no: i + 1, k }));
const temizle = (gunler: string[]) => sql.begin(async (t) => { await t`set local mahalle.duzeltme = 'evet'`; await t`delete from mahalle.gunluk where gun = any(${gunler})`; });
geriKoy = await gunlukKoru("mahalle", [gun(-1), gun(1)]);

test("8180 mahalle: oyun satırı, eşitlik ikincil; tablo ve servis uçları istemciye kapalı", async () => {
  const [o] = await sql`select ayarlar from ortak.oyunlar where id = 'mahalle'`;
  assert.equal(o!.ayarlar.siralama.esitlik, "ikincil");
  for (const rol of ["anon", "authenticated"]) {
    await assert.rejects(sql.begin(async (t) => { await t.unsafe(`set local role ${rol}`); await t`select * from mahalle.gunluk limit 1`; }), /permission denied/, rol);
  }
  assert.ok((await istemci().rpc("mahalle_gunluk_oku", { p_gun: gun(0) })).error);
  assert.ok((await istemci().rpc("mahalle_gunluk_yukle", { p_satirlar: [], p_surum: "x" })).error);
});

test("8270 mahalle lig: kademeler, 30'luk grupta 7 çıkar 5 iner, bayrak kapalı", async () => {
  const [o] = await sql`select ayarlar from ortak.oyunlar where id = 'mahalle'`;
  const l = o!.ayarlar.lig;
  assert.equal(l.kademeler.length, 8);
  assert.equal(l.esitlik, "ikincil");
  assert.equal(Math.floor(30 * l.cikis_orani), 7);
  assert.equal(Math.floor(30 * l.inis_orani), 5);
  assert.equal(o!.ayarlar.bayraklar.lig_acik, false);
  assert.equal(o!.ayarlar.siralama.esitlik, "ikincil", "mevcut ayarlar korunur");
});

test("8180 mahalle.gunluk: beş kutu şartı, açılmış gün korunur, gelecek gün yalnız içerik değişince güncellenir", async () => {
  const dun = gun(-1), yarin = gun(1);
  await temizle([dun, yarin]);
  const sv = yonetici();
  const y = (await sv.rpc("mahalle_gunluk_yukle", { p_satirlar: [{ gun: dun, kutular: bes("a") }, { gun: yarin, kutular: bes("b") }], p_surum: "v1" })).data;
  assert.equal(y.yazilan, 2);
  const y2 = (await sv.rpc("mahalle_gunluk_yukle", { p_satirlar: [{ gun: dun, kutular: bes("z") }, { gun: yarin, kutular: bes("b") }, { gun: yarin, kutular: bes("c") }], p_surum: "v2" })).data;
  assert.equal(y2.yazilan, 1, "açılmış gün ve aynı içerik atlanır");
  assert.deepEqual((await sv.rpc("mahalle_gunluk_oku", { p_gun: dun })).data.kutular, bes("a"));
  assert.deepEqual((await sv.rpc("mahalle_gunluk_oku", { p_gun: yarin })).data.kutular, bes("c"));
  await assert.rejects(sql`update mahalle.gunluk set kutular = ${sql.json(bes("q"))} where gun = ${dun}`, /acilmis_gun_degisemez/);
  await assert.rejects(sql`insert into mahalle.gunluk (gun, kutular, icerik_surumu) values (${gun(5)}, '[1,2]', 'x')`, /check/);
  await temizle([dun, yarin]);
});
