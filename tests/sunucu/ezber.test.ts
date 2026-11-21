// Göç 8100 (Ezber Bozan): oyun satırı ve ürün, gizli günlük tablo, açılmış gün koruması, ipucu hakkı (sırayla, aynı
// istek aynı sonuç), hesap silmede ipucu kayıtları gider.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { istemci, kaliciKullanici, sql, yonetici } from "./yardimci.ts";

after(() => sql.end());

const gun = (fark: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + fark * 864e5));
const satir = (g: string, id: string) => ({ gun: g, challenge_id: id, bulmaca: { b: id }, en_kisa: 4, ilk_hamle: { h: 1 }, hedef_beklenti: null, aile: "A", kaynak_sinif: "k", motor_surumu: "1.0.0" });
// Yerel yığında oyunun gerçek içeriği de olabilir (oyun oturumu yükler): sınanan günler ve test kimlikleri temizlenir.
const temizle = () => sql.begin(async (t) => { await t`set local ezber.duzeltme = 'evet'`; await t`delete from ezber.gunluk where challenge_id like 'test-%' or gun between ${gun(-1)}::date and ${gun(1)}::date`; });

test("8100 ezber: oyun satırı, ürün; tablolar ve servis uçları istemciye kapalı", async () => {
  const [o] = await sql`select ayarlar from ortak.oyunlar where id = 'ezber'`;
  assert.equal(o!.ayarlar.hesap.silme_fonksiyonu, "ezber.oyuncu_verisini_sil");
  const [u] = await sql`select hak from ortak.urunler where urun = 'ezber_tam_acilim'`;
  assert.equal(u!.hak, "tam_acilim");
  for (const t of ["gunluk", "ipucu"]) {
    await assert.rejects(sql.begin(async (x) => { await x`set local role anon`; await x.unsafe(`select * from ezber.${t} limit 1`); }), /permission denied/, t);
  }
  for (const [fn, a] of [["ezber_gunluk_oku", { p_gun: gun(0) }], ["ezber_ipucu", { p_kullanici: crypto.randomUUID(), p_gun: gun(0) }], ["ezber_gunluk_yukle", { p_satirlar: [], p_surum: "x" }]] as const) {
    assert.ok((await istemci().rpc(fn, a)).error, `${fn} anon'a kapalı`);
  }
});

test("8100 ezber yükleme ve açılmış gün", async () => {
  await temizle();
  const sv = yonetici();
  const [d, b, y] = [gun(-1), gun(0), gun(1)];
  const r = (await sv.rpc("ezber_gunluk_yukle", { p_satirlar: [satir(d, "test-d"), satir(b, "test-b"), satir(y, "test-y")], p_surum: "1.0.0" })).data;
  assert.equal(r.yazilan, 3);
  const r2 = (await sv.rpc("ezber_gunluk_yukle", { p_satirlar: [{ ...satir(d, "test-d"), aile: "Z" }, { ...satir(y, "test-y"), aile: "Z" }], p_surum: "1.0.1" })).data;
  assert.equal(r2.yazilan, 1, "yalnız gelecek gün güncellenir");
  assert.equal((await sv.rpc("ezber_gunluk_oku", { p_gun: d })).data.aile, "A");
  assert.equal((await sv.rpc("ezber_gunluk_oku", { p_gun: y })).data.aile, "Z");
  assert.equal((await sv.rpc("ezber_gunluk_oku", { p_gun: b })).data.hedef_beklenti, null);
  await assert.rejects(sql`update ezber.gunluk set aile = 'Q' where gun = ${d}`, /acilmis_gun_degisemez/);
  await temizle();
});

test("8100 ezber ipucu: sırayla, aynı istek aynı sonuç; hesap silinince kayıt gider", async () => {
  const k = await kaliciKullanici();
  const sv = yonetici();
  const g = gun(0);
  assert.deepEqual((await sv.rpc("ezber_ipucu", { p_kullanici: k.id, p_gun: g })).data, []);
  const atla = await sv.rpc("ezber_ipucu", { p_kullanici: k.id, p_gun: g, p_basamak: 2 });
  assert.match(atla.error?.message ?? "", /ipucu_sirasi/, "basamak atlanamaz");
  assert.deepEqual((await sv.rpc("ezber_ipucu", { p_kullanici: k.id, p_gun: g, p_basamak: 1 })).data, [1]);
  assert.deepEqual((await sv.rpc("ezber_ipucu", { p_kullanici: k.id, p_gun: g, p_basamak: 1 })).data, [1], "tekrar aynı");
  assert.deepEqual((await sv.rpc("ezber_ipucu", { p_kullanici: k.id, p_gun: g, p_basamak: 2 })).data, [1, 2]);
  await sql`select ezber.oyuncu_verisini_sil(${k.id})`;
  assert.deepEqual((await sv.rpc("ezber_ipucu", { p_kullanici: k.id, p_gun: g })).data, []);
  await sv.rpc("ezber_ipucu", { p_kullanici: k.id, p_gun: g, p_basamak: 1 });
  await sv.auth.admin.deleteUser(k.id);
  const [n] = await sql`select count(*)::int as n from ezber.ipucu where kullanici_id = ${k.id}`;
  assert.equal(n!.n, 0, "hesap silinince iz kalmaz");
});
