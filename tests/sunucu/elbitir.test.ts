// Göç 8470 (El Bitir): oyun satırı, gizli günlük ana el tablosu yalnız servis rolüne, açılmış gün koruması, yükleme kuralı, yönetim kaydı.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { istemci, sql, yonetici, gunlukKoru } from "./yardimci.ts";

let geriKoy: (() => Promise<void>) | undefined;
after(async () => { await geriKoy?.(); await sql.end(); });

const gun = (fark: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + fark * 864e5));
const temizle = (gunler: string[]) => sql.begin(async (t) => { await t`set local elbitir.duzeltme = 'evet'`; await t`delete from elbitir.gunluk where gun = any(${gunler})`; });
geriKoy = await gunlukKoru("elbitir", [gun(-1), gun(1)]);

test("8470 elbitir: oyun satırı (lig yok); tablo ve servis uçları istemciye kapalı", async () => {
  const [o] = await sql`select ayarlar from ortak.oyunlar where id = 'elbitir'`;
  assert.ok(o, "satır var");
  assert.equal(o!.ayarlar.siralama.esitlik, "ikincil");
  assert.equal(o!.ayarlar.lig, undefined);
  for (const rol of ["anon", "authenticated"]) {
    await assert.rejects(sql.begin(async (t) => { await t.unsafe(`set local role ${rol}`); await t`select * from elbitir.gunluk limit 1`; }), /permission denied/, rol);
  }
  assert.ok((await istemci().rpc("elbitir_gunluk_oku", { p_gun: gun(0) })).error);
  assert.ok((await istemci().rpc("elbitir_gunluk_yukle", { p_satirlar: [], p_surum: "x" })).error);
});

test("8470 elbitir.gunluk: açılmış gün korunur, gelecek gün yalnız değişince güncellenir, cevap ayrı alanda, yönetim kaydı yazılır", async () => {
  const dun = gun(-1), yarin = gun(1);
  await temizle([dun, yarin]);
  const sv = yonetici();
  const el = (n: number) => ({ gun: dun, icerik: { gosterge: n }, par: 3, cevap: { al: "D" } });
  const r1 = (await sv.rpc("elbitir_gunluk_yukle", { p_satirlar: [el(1), { ...el(1), gun: yarin }], p_surum: "v1" })).data;
  assert.equal(r1.yazilan, 2);
  assert.equal(typeof r1.kalan_gun, "number");
  const r2 = (await sv.rpc("elbitir_gunluk_yukle", { p_satirlar: [el(9), { ...el(1), gun: yarin }, { ...el(2), gun: yarin }], p_surum: "v2" })).data;
  assert.equal(r2.yazilan, 1);
  const d = (await sv.rpc("elbitir_gunluk_oku", { p_gun: dun })).data;
  assert.deepEqual(d.icerik, { gosterge: 1 });
  assert.equal(d.par, 3);
  assert.deepEqual(d.cevap, { al: "D" });
  assert.deepEqual((await sv.rpc("elbitir_gunluk_oku", { p_gun: yarin })).data.icerik, { gosterge: 2 });
  await assert.rejects(sql`update elbitir.gunluk set par = 9 where gun = ${dun}`, /acilmis_gun_degisemez/);
  const [k] = await sql`select count(*)::int as n from ortak.yonetim_kaydi where tablo = 'elbitir.gunluk'`;
  assert.ok(k!.n >= 3, "yönetim kaydı");
  await temizle([dun, yarin]);
});
