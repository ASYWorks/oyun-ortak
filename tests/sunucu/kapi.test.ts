// Göç 8190 (Kapı Ustası): oyun satırı, gizli günlük tablo yalnız servis rolüne, açılmış gün koruması, yükleme kuralı.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { istemci, sql, yonetici } from "./yardimci.ts";

after(() => sql.end());

const gun = (fark: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + fark * 864e5));
const temizle = (gunler: string[]) => sql.begin(async (t) => { await t`set local kapi.duzeltme = 'evet'`; await t`delete from kapi.gunluk where gun = any(${gunler})`; });

test("8190 kapi: oyun satırı; tablo ve servis uçları istemciye kapalı", async () => {
  const [o] = await sql`select ayarlar from ortak.oyunlar where id = 'kapi'`;
  assert.ok(o, "satır var");
  assert.equal(o!.ayarlar.siralama.esitlik, "ikincil");
  for (const rol of ["anon", "authenticated"]) {
    await assert.rejects(sql.begin(async (t) => { await t.unsafe(`set local role ${rol}`); await t`select * from kapi.gunluk limit 1`; }), /permission denied/, rol);
  }
  assert.ok((await istemci().rpc("kapi_gunluk_oku", { p_gun: gun(0) })).error);
});

test("8190 kapi.gunluk: açılmış gün korunur, gelecek gün yalnız içerik değişince güncellenir", async () => {
  const dun = gun(-1), yarin = gun(1);
  await temizle([dun, yarin]);
  const sv = yonetici();
  assert.equal((await sv.rpc("kapi_gunluk_yukle", { p_satirlar: [{ gun: dun, icerik: { a: 1 } }, { gun: yarin, icerik: { a: 1 } }], p_surum: "v1" })).data.yazilan, 2);
  assert.equal((await sv.rpc("kapi_gunluk_yukle", { p_satirlar: [{ gun: dun, icerik: { a: 9 } }, { gun: yarin, icerik: { a: 1 } }, { gun: yarin, icerik: { a: 2 } }], p_surum: "v2" })).data.yazilan, 1);
  assert.deepEqual((await sv.rpc("kapi_gunluk_oku", { p_gun: dun })).data.icerik, { a: 1 });
  assert.deepEqual((await sv.rpc("kapi_gunluk_oku", { p_gun: yarin })).data.icerik, { a: 2 });
  await assert.rejects(sql`update kapi.gunluk set icerik = '{"q":1}' where gun = ${dun}`, /acilmis_gun_degisemez/);
  await temizle([dun, yarin]);
});
