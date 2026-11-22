// Göç 8200 (Koz Hesabı): oyun satırı, gizli günlük tablo yalnız servis rolüne, açılmış gün koruması, yükleme kuralı.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { istemci, sql, yonetici } from "./yardimci.ts";

after(() => sql.end());

const gun = (fark: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + fark * 864e5));
const temizle = (gunler: string[]) => sql.begin(async (t) => { await t`set local koz.duzeltme = 'evet'`; await t`delete from koz.gunluk where gun = any(${gunler})`; });

test("8200 koz: oyun satırı; tablo ve servis uçları istemciye kapalı", async () => {
  const [o] = await sql`select ayarlar from ortak.oyunlar where id = 'koz'`;
  assert.ok(o, "satır var");
  assert.equal(o!.ayarlar.siralama.esitlik, "ikincil");
  for (const rol of ["anon", "authenticated"]) {
    await assert.rejects(sql.begin(async (t) => { await t.unsafe(`set local role ${rol}`); await t`select * from koz.gunluk limit 1`; }), /permission denied/, rol);
  }
  assert.ok((await istemci().rpc("koz_gunluk_oku", { p_gun: gun(0) })).error);
});

test("8200 koz.gunluk: açılmış gün korunur, gelecek gün yalnız içerik değişince güncellenir", async () => {
  const dun = gun(-1), yarin = gun(1);
  await temizle([dun, yarin]);
  const sv = yonetici();
  assert.equal((await sv.rpc("koz_gunluk_yukle", { p_satirlar: [{ gun: dun, eller: { a: 1 } }, { gun: yarin, eller: { a: 1 } }], p_surum: "v1" })).data.yazilan, 2);
  assert.equal((await sv.rpc("koz_gunluk_yukle", { p_satirlar: [{ gun: dun, eller: { a: 9 } }, { gun: yarin, eller: { a: 1 } }, { gun: yarin, eller: { a: 2 } }], p_surum: "v2" })).data.yazilan, 1);
  assert.deepEqual((await sv.rpc("koz_gunluk_oku", { p_gun: dun })).data.eller, { a: 1 });
  assert.deepEqual((await sv.rpc("koz_gunluk_oku", { p_gun: yarin })).data.eller, { a: 2 });
  await assert.rejects(sql`update koz.gunluk set eller = '{"q":1}' where gun = ${dun}`, /acilmis_gun_degisemez/);
  await temizle([dun, yarin]);
});
