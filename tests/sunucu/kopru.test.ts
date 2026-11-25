// Göç 8490 (Kelime Köprüsü): oyun satırı (eşitlik ortak, lig yok); gizli günlük tablo (gün × parça) yalnız servis rolüne;
// açılmış gün koruması, yükleme kuralı, yönetim kaydı.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { istemci, sql, yonetici, gunlukKoru } from "./yardimci.ts";

let geriKoy: (() => Promise<void>) | undefined;
after(async () => { await geriKoy?.(); await sql.end(); });

const gun = (fark: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + fark * 864e5));
const temizle = (gunler: string[]) => sql.begin(async (t) => { await t`set local kopru.duzeltme = 'evet'`; await t`delete from kopru.gunluk where gun = any(${gunler})`; });
geriKoy = await gunlukKoru("kopru", [gun(-1), gun(1)]);

const satir = (g: string, parca: string, n: number) => ({ gun: g, parca, birim: { uclar: [n] }, par: 4, graf_surumu: "g1", motor_surumu: "m1", ornek_yollar: [["a", "b"]] });

test("8490 kopru: oyun satırı (eşitlik ortak, lig yok); tablo ve uçlar istemciye kapalı", async () => {
  const [o] = await sql`select ad, ayarlar from ortak.oyunlar where id = 'kopru'`;
  assert.ok(o, "satır var");
  assert.equal(o!.ad, "Kelime Köprüsü");
  assert.equal(o!.ayarlar.siralama.esitlik, "ortak");
  assert.equal(o!.ayarlar.lig, undefined);
  for (const rol of ["anon", "authenticated"]) {
    await assert.rejects(sql.begin(async (t) => { await t.unsafe(`set local role ${rol}`); await t`select * from kopru.gunluk limit 1`; }), /permission denied/, rol);
  }
  assert.ok((await istemci().rpc("kopru_gunluk_oku", { p_gun: gun(0) })).error);
});

test("8490 kopru.gunluk: gün × parça; açılmış gün korunur; gelecek yalnız değişince; yönetim kaydı", async () => {
  const dun = gun(-1), yarin = gun(1);
  await temizle([dun, yarin]);
  const sv = yonetici();
  const r1 = (await sv.rpc("kopru_gunluk_yukle", { p_satirlar: [satir(dun, "kopru", 1), satir(dun, "mini", 1), satir(yarin, "kopru", 1)], p_surum: "v1" })).data;
  assert.equal(r1.yazilan, 3);
  assert.equal(typeof r1.kalan_gun, "number");
  const r2 = (await sv.rpc("kopru_gunluk_yukle", { p_satirlar: [satir(dun, "kopru", 9), satir(yarin, "kopru", 1), satir(yarin, "usta", 2)], p_surum: "v2" })).data;
  assert.equal(r2.yazilan, 1, "yalnız yeni gelecek parça");
  const d = (await sv.rpc("kopru_gunluk_oku", { p_gun: dun })).data;
  assert.equal(d.length, 2);
  assert.deepEqual(d.find((x: { parca: string }) => x.parca === "kopru").birim, { uclar: [1] });
  await assert.rejects(sql`update kopru.gunluk set par = 9 where gun = ${dun} and parca = 'kopru'`, /acilmis_gun_degisemez/);
  const [k] = await sql`select count(*)::int as n from ortak.yonetim_kaydi where tablo = 'kopru.gunluk'`;
  assert.ok(k!.n >= 4);
  await temizle([dun, yarin]);
});
