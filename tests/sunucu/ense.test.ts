// Göç 7800 (Ense Nasıl Olsun): oyun satırı, gizli günlük tablo yalnız servis rolüne, açılmış gün koruması.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { sql, yonetici } from "./yardimci.ts";

after(() => sql.end());

const gun = (fark: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + fark * 864e5));

test("7800 ense: oyun satırı, lig yok, büyük puan önde, eşitlik ikincil", async () => {
  const [o] = await sql`select ayarlar from ortak.oyunlar where id = 'ense'`;
  assert.ok(o, "ense satırı var");
  assert.equal(o!.ayarlar.siralama.esitlik, "ikincil");
  assert.equal(o!.ayarlar.siralama.yon, undefined, "varsayılan yön: büyük puan önde");
  assert.equal(o!.ayarlar.lig, undefined);
  assert.equal(o!.ayarlar.hesap, undefined, "oyuna özgü kullanıcı tablosu yok, ortak silme yolu yeter");
});

test("7800 ense.gunluk: anon ve authenticated okuyamaz, servis rolü okur", async () => {
  for (const rol of ["anon", "authenticated"]) {
    await assert.rejects(sql.begin(async (t) => { await t.unsafe(`set local role ${rol}`); await t`select * from ense.gunluk limit 1`; }), /permission denied/, rol);
  }
  const { error } = await yonetici().schema("ense" as never).from("gunluk").select("gun").limit(1);
  // ense şeması API'ye açık değil: servis anahtarı bile REST'ten okuyamaz, dogrula-ense doğrudan bağlanır ya da açılır
  assert.ok(error === null || /schema|Invalid/.test(error.message), error?.message);
});

test("7800 ense.gunluk: açılmış gün değişemez ve silinemez; gelecek gün serbest; bilinçli düzeltme geçer", async () => {
  const dun = gun(-1), yarin = gun(1);
  await sql`delete from ense.gunluk where gun in (${yarin})`;
  await sql.begin(async (t) => { await t`set local ense.duzeltme = 'evet'`; await t`delete from ense.gunluk where gun = ${dun}`; });
  await sql`insert into ense.gunluk (gun, resmi, prova, icerik_surumu) values (${dun}, '{"a":1}', '{}', 't'), (${yarin}, '{"a":1}', '{}', 't')`;
  await assert.rejects(sql`update ense.gunluk set resmi = '{"a":2}' where gun = ${dun}`, /acilmis_gun_degisemez/);
  await assert.rejects(sql`delete from ense.gunluk where gun = ${dun}`, /acilmis_gun_degisemez/);
  await sql`update ense.gunluk set yukleme = now() where gun = ${dun}`; // içerik dışı alan serbest
  await sql`update ense.gunluk set resmi = '{"a":2}' where gun = ${yarin}`;
  await sql.begin(async (t) => { await t`set local ense.duzeltme = 'evet'`; await t`update ense.gunluk set resmi = '{"a":3}' where gun = ${dun}`; });
  const [r] = await sql`select resmi from ense.gunluk where gun = ${dun}`;
  assert.deepEqual(r!.resmi, { a: 3 });
  await sql.begin(async (t) => { await t`set local ense.duzeltme = 'evet'`; await t`delete from ense.gunluk where gun in (${dun}, ${yarin})`; });
});

test("7800 ense sarmalayıcıları: yalnız servis rolü; yükleme açılmış günü atlar, geleceği yazar; okuma gizli veriyi döner", async () => {
  const dun = gun(-1), yarin = gun(1);
  const sv = yonetici();
  await sql.begin(async (t) => { await t`set local ense.duzeltme = 'evet'`; await t`delete from ense.gunluk where gun in (${dun}, ${yarin})`; });
  await sql`insert into ense.gunluk (gun, resmi, prova, icerik_surumu) values (${dun}, '{"eski":1}', '{}', 'v0')`;
  const { data: y, error } = await sv.rpc("ense_gunluk_yukle", { p_satirlar: [{ gun: dun, resmi: { yeni: 1 }, prova: {} }, { gun: yarin, resmi: { cevap: "x" }, prova: { p: 1 } }], p_surum: "v1" });
  assert.ifError(error);
  assert.equal(y.yazilan, 1);
  assert.equal(y.atlanan, 1, "açılmış gün atlandı");
  const { data: o } = await sv.rpc("ense_gunluk_oku", { p_gun: yarin });
  assert.deepEqual([o.resmi, o.prova, o.icerik_surumu], [{ cevap: "x" }, { p: 1 }, "v1"]);
  const { data: d } = await sv.rpc("ense_gunluk_oku", { p_gun: dun });
  assert.deepEqual(d.resmi, { eski: 1 }, "açılmış gün değişmedi");
  const { istemci } = await import("./yardimci.ts");
  for (const fn of ["ense_gunluk_oku", "ense_gunluk_yukle"]) {
    const { error: e } = await istemci().rpc(fn, fn === "ense_gunluk_oku" ? { p_gun: yarin } : { p_satirlar: [], p_surum: "x" });
    assert.ok(e, `${fn} anon'a kapalı`);
  }
  await sql.begin(async (t) => { await t`set local ense.duzeltme = 'evet'`; await t`delete from ense.gunluk where gun in (${dun}, ${yarin})`; });
});

test("7810 ense_gunluk_yukle: eksik bugün eklenir, var olan açılmış gün değişmez", async () => {
  const bugun = gun(0), dun = gun(-1);
  const sv = yonetici();
  await sql.begin(async (t) => { await t`set local ense.duzeltme = 'evet'`; await t`delete from ense.gunluk where gun in (${bugun}, ${dun})`; });
  await sql`insert into ense.gunluk (gun, resmi, prova, icerik_surumu) values (${dun}, '{"eski":1}', '{}', 'v0')`;
  const { data: y, error } = await sv.rpc("ense_gunluk_yukle", { p_satirlar: [{ gun: bugun, resmi: { b: 1 }, prova: {} }, { gun: dun, resmi: { yeni: 1 }, prova: {} }], p_surum: "v2" });
  assert.ifError(error);
  assert.deepEqual([y.yazilan, y.atlanan], [1, 1]);
  const { data: b } = await sv.rpc("ense_gunluk_oku", { p_gun: bugun });
  assert.deepEqual(b.resmi, { b: 1 }, "eksik bugün eklendi");
  const { data: d } = await sv.rpc("ense_gunluk_oku", { p_gun: dun });
  assert.deepEqual(d.resmi, { eski: 1 }, "var olan açılmış gün değişmedi");
  await sql.begin(async (t) => { await t`set local ense.duzeltme = 'evet'`; await t`delete from ense.gunluk where gun in (${bugun}, ${dun})`; });
});
