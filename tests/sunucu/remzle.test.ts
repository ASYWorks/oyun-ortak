// Göç 8000 (Remzle): oyun satırı, gizli anahtar tablosu yalnız servis rolüne, açılmış gün koruması ve yönetim kaydı,
// yükleme kuralları (eksik satır eklenir; var olan yalnız gelecekte ve sürüm farklıysa güncellenir).
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { gunlukKoru, istemci, sql, yonetici } from "./yardimci.ts";


const gun = (fark: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + fark * 864e5));
// ÖG-53: paylaşılan yerel yığında oyunun yakın gün satırları test sonunda aynen geri konur.
const geriKoy = await gunlukKoru("remzle", [gun(-1), gun(0), gun(1)], { tablo: "gunluk_anahtar" });
after(async () => { await geriKoy(); await sql.end(); });
const oz = (c: string) => c.repeat(64).slice(0, 64);
const satir = (g: string, k: number, c: string) => ({ gun: g, katman: k, cevap_ozet: oz(c), ipuclari: ["a", "b", "c"], zorluk: 2, gosterim: { k, c } });
const temizle = (gunler: string[]) => sql.begin(async (t) => { await t`set local remzle.duzeltme = 'evet'`; await t`delete from remzle.gunluk_anahtar where gun = any(${gunler})`; });

test("8000 remzle: oyun satırı ve tablo istemciye kapalı", async () => {
  const [o] = await sql`select ayarlar from ortak.oyunlar where id = 'remzle'`;
  assert.equal(o!.ayarlar.siralama.esitlik, "ikincil");
  assert.equal(o!.ayarlar.lig, undefined);
  for (const rol of ["anon", "authenticated"]) {
    await assert.rejects(sql.begin(async (t) => { await t.unsafe(`set local role ${rol}`); await t`select * from remzle.gunluk_anahtar limit 1`; }), /permission denied/, rol);
  }
  for (const [fn, a] of [["remzle_anahtar_oku", { p_gun: gun(1) }], ["remzle_anahtar_yukle", { p_satirlar: [], p_surum: "x" }]] as const) {
    assert.ok((await istemci().rpc(fn, a)).error, `${fn} anon'a kapalı`);
  }
});

test("8000 remzle yükleme: eksik bugün eklenir; açılmış gün değişmez; gelecek gün yalnız yeni sürümle güncellenir; okuma katman sırasıyla", async () => {
  const dun = gun(-1), bugun = gun(0), yarin = gun(1);
  await temizle([dun, bugun, yarin]);
  const sv = yonetici();
  await sql`insert into remzle.gunluk_anahtar (gun, katman, cevap_ozet, ipuclari, zorluk, icerik_surumu) values (${dun}, 1, ${oz("e")}, '["x","y","z"]', 1, 'v0')`.catch(async () => sql`insert into remzle.gunluk_anahtar (gun, katman, cevap_ozet, ipuclari, zorluk, gosterim, icerik_surumu) values (${dun}, 1, ${oz("e")}, '["x","y","z"]', 1, '{}', 'v0')`);
  const y1 = (await sv.rpc("remzle_anahtar_yukle", { p_satirlar: [satir(dun, 1, "a"), satir(bugun, 1, "b"), satir(yarin, 2, "c"), satir(yarin, 1, "d")], p_surum: "v1" })).data;
  assert.deepEqual([y1.yazilan, y1.atlanan], [3, 1]);
  const y2 = (await sv.rpc("remzle_anahtar_yukle", { p_satirlar: [satir(yarin, 1, "f")], p_surum: "v1" })).data;
  assert.equal(y2.yazilan, 0, "aynı sürüm yeniden yazılmaz");
  const y3 = (await sv.rpc("remzle_anahtar_yukle", { p_satirlar: [satir(yarin, 1, "f")], p_surum: "v2" })).data;
  assert.equal(y3.yazilan, 1, "gelecek gün yeni sürümle güncellenir");
  const { data: o } = await sv.rpc("remzle_anahtar_oku", { p_gun: yarin });
  assert.deepEqual(o.map((r: { katman: number }) => r.katman), [1, 2]);
  assert.equal(o[0].cevap_ozet, oz("f"));
  const { data: d } = await sv.rpc("remzle_anahtar_oku", { p_gun: dun });
  assert.equal(d[0].cevap_ozet, oz("e"), "açılmış gün değişmedi");
  assert.deepEqual((await sv.rpc("remzle_anahtar_oku", { p_gun: gun(30) })).data, []);
  await assert.rejects(sql`update remzle.gunluk_anahtar set cevap_ozet = ${oz("9")} where gun = ${dun}`, /acilmis_gun_degisemez/);
  await assert.rejects(sql`insert into remzle.gunluk_anahtar (gun, katman, cevap_ozet, ipuclari, zorluk, icerik_surumu) values (${gun(5)}, 1, 'kisa', '[]', 1, 'v')`, /check|null/);
  const [k] = await sql`select count(*)::int as n from ortak.yonetim_kaydi where tablo like '%gunluk_anahtar' and anahtar = ${yarin}`;
  assert.ok(k!.n >= 3, `yönetim kaydı yazıldı (${k!.n})`);
  await temizle([dun, bugun, yarin]);
});

test("8010 remzle gösterim: okuma gösterimi döner, gösterimsiz yükleme reddedilir, açılmış günün gösterimi değişmez", async () => {
  const dun = gun(-1), yarin = gun(1);
  await temizle([dun, yarin]);
  const sv = yonetici();
  await sv.rpc("remzle_anahtar_yukle", { p_satirlar: [satir(dun, 1, "a"), satir(yarin, 1, "b")], p_surum: "v1" });
  assert.deepEqual((await sv.rpc("remzle_anahtar_oku", { p_gun: yarin })).data[0].gosterim, { k: 1, c: "b" });
  const { error } = await sv.rpc("remzle_anahtar_yukle", { p_satirlar: [{ gun: gun(9), katman: 1, cevap_ozet: oz("a"), ipuclari: ["a", "b", "c"], zorluk: 1 }], p_surum: "v1" });
  assert.match(error?.message ?? "", /gosterim_gerekli/);
  await assert.rejects(sql`update remzle.gunluk_anahtar set gosterim = '{"x":1}' where gun = ${dun}`, /acilmis_gun_degisemez/);
  await temizle([dun, yarin]);
});

test("8150 remzle çözüm: yüklenir ve okunur, yoksa null; biçim denetlenir; açılmış günün çözümü değişmez", async () => {
  const dun = gun(-1), yarin = gun(1), obur = gun(2);
  await temizle([dun, yarin, obur]);
  const sv = yonetici();
  const cozum = { cevap: "KAPI", adimlar: ["bir", "iki"] };
  const y = await sv.rpc("remzle_anahtar_yukle", { p_satirlar: [{ ...satir(dun, 1, "a"), cozum }, { ...satir(yarin, 1, "b"), cozum }, satir(obur, 1, "c")], p_surum: "v1" });
  assert.ifError(y.error);
  assert.deepEqual((await sv.rpc("remzle_anahtar_oku", { p_gun: yarin })).data[0].cozum, cozum);
  assert.equal((await sv.rpc("remzle_anahtar_oku", { p_gun: obur })).data[0].cozum, null, "çözümsüz satır null");
  const bozuk = await sv.rpc("remzle_anahtar_yukle", { p_satirlar: [{ ...satir(gun(3), 1, "d"), cozum: { cevap: "X", adimlar: [] } }], p_surum: "v1" });
  assert.match(bozuk.error?.message ?? "", /cozum_bicimi/);
  await assert.rejects(sql`update remzle.gunluk_anahtar set cozum = null where gun = ${dun}`, /acilmis_gun_degisemez/);
  assert.ok((await istemci().rpc("remzle_anahtar_oku", { p_gun: yarin })).error, "istemci okuyamaz");
  await temizle([dun, yarin, obur, gun(3)]);
});
