// Göç 7900 (Sahte Masası): oyun satırı, gizli deste tablosu, açılmış gün koruması, takvim ve bölüm (misafire açık,
// gelecek ve dün 03:00'ten önce verilmez), servis rolü yükleme kuralları.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { gunlukKoru, istemci, sql, yonetici } from "./yardimci.ts";


const gun = (fark: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + fark * 864e5));
// ÖG-53: paylaşılan yerel yığında oyunun yakın gün satırları test sonunda aynen geri konur.
const geriKoy = await gunlukKoru("sahte", [gun(-2), gun(-1), gun(0), gun(1)], { tablo: "desteler" });
after(async () => { await geriKoy(); await sql.end(); });
const saat = Number(new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Istanbul", hour: "2-digit", hour12: false }).format(new Date()));
const deste = (g: string, no: number, ozet: string) => ({ gun: g, no, surum: 1, tam: { cevap: no }, acik: { soru: no }, ozet });
// Yerel yığında oyunun gerçek desteleri de olabilir (oyun oturumu yükler): sınanan günler ve test numaraları temizlenir.
const temizle = () => sql.begin(async (t) => { await t`set local sahte.duzeltme = 'evet'`; await t`delete from sahte.desteler where no >= 900000 or gun between ${gun(-2)}::date and ${gun(1)}::date`; });

test("7900 sahte: oyun satırı; tablo ve servis uçları istemciye kapalı", async () => {
  const [o] = await sql`select ayarlar from ortak.oyunlar where id = 'sahte'`;
  assert.equal(o!.ayarlar.siralama.esitlik, "ortak", "SM-4 (göç 8140)");
  for (const rol of ["anon", "authenticated"]) {
    await assert.rejects(sql.begin(async (t) => { await t.unsafe(`set local role ${rol}`); await t`select * from sahte.desteler limit 1`; }), /permission denied/, rol);
  }
  assert.ok((await istemci().rpc("sahte_deste_oku", { p_gun: gun(0) })).error);
  assert.ok((await istemci().rpc("sahte_deste_yukle", { p_satirlar: [] })).error);
});

test("7900 sahte: yükleme, takvim ve bölüm kuralları", async () => {
  await temizle();
  const sv = yonetici();
  const [g2, g1, g0, y1] = [gun(-2), gun(-1), gun(0), gun(1)];
  const y = (await sv.rpc("sahte_deste_yukle", { p_satirlar: [deste(g2, 900002, "a"), deste(g1, 900001, "b"), deste(g0, 900000, "c"), deste(y1, 900003, "d")] })).data;
  assert.equal(y.yazilan, 4);
  // açılmış gün yeniden yüklemede değişmez; gelecek gün yalnız özet değişince güncellenir
  const y2 = (await sv.rpc("sahte_deste_yukle", { p_satirlar: [{ ...deste(g2, 900002, "z"), tam: { cevap: "x" } }, deste(y1, 900003, "d"), { ...deste(y1, 900003, "e"), tam: { cevap: 7 } }] })).data;
  assert.equal(y2.yazilan, 1);
  assert.deepEqual((await sv.rpc("sahte_deste_oku", { p_gun: g2 })).data.tam, { cevap: 900002 });
  assert.deepEqual((await sv.rpc("sahte_deste_oku", { p_gun: y1 })).data.tam, { cevap: 7 });

  const misafir = istemci();
  const { data: t, error } = await misafir.rpc("sahte_takvim");
  assert.ifError(error);
  const benim = t.gunler.filter((x: { no: number }) => x.no >= 900000);
  assert.deepEqual(benim.map((x: { gun: string }) => x.gun), [g2, g1, g0], "gelecek gün takvimde yok");
  assert.equal(benim.find((x: { gun: string }) => x.gun === g0).bolum, false, "bugün bölüm değil");
  assert.equal(benim.find((x: { gun: string }) => x.gun === g2).bolum, true);

  assert.deepEqual((await misafir.rpc("sahte_bolum", { p_gun: g2 })).data.deste, { cevap: 900002 }, "geçmiş gün misafire açık");
  assert.equal((await misafir.rpc("sahte_bolum", { p_gun: g0 })).data, null, "bugün kapalı");
  assert.equal((await misafir.rpc("sahte_bolum", { p_gun: y1 })).data, null, "gelecek kapalı");
  const dun = (await misafir.rpc("sahte_bolum", { p_gun: g1 })).data;
  if (saat >= 3) assert.ok(dun, "dün 03:00'ten sonra açık"); else assert.equal(dun, null, "dün 03:00'ten önce kapalı");

  await assert.rejects(sql`update sahte.desteler set ozet = 'q' where gun = ${g2}`, /acilmis_gun_degisemez/);
  await temizle();
});

test("8560 sahte: kırpma bugünü, yarını ve açılmış günü silmez; sonrası silinir; yalnız servis rolü", async () => {
  // Yerel yığındaki gerçek gelecek desteler test boyunca saklanır, sonunda aynen geri konur.
  const sakla = await sql`select * from sahte.desteler where gun > ${gun(1)}::date and no < 900000`;
  try {
    await temizle();
    await sql`delete from sahte.desteler where gun > ${gun(1)}::date`;
    const sv = yonetici();
    const satir = [-2, -1, 0, 1, 2, 3, 4].map((f, i) => deste(gun(f), 900100 + i, "k" + i));
    assert.equal((await sv.rpc("sahte_deste_yukle", { p_satirlar: satir })).data.yazilan, 7);
    assert.ok((await istemci().rpc("sahte_deste_kirp", { p_son: gun(1) })).error, "misafir çağıramaz");

    const k1 = (await sv.rpc("sahte_deste_kirp", { p_son: gun(2) })).data;
    assert.deepEqual(k1, { silinen: 2, son_gun: gun(2) }, "p_son sonrası silinir");
    const k2 = (await sv.rpc("sahte_deste_kirp", { p_son: gun(-5) })).data;
    assert.deepEqual(k2, { silinen: 1, son_gun: gun(1) }, "geçmiş p_son verilse de bugün ve yarın kalır");
    const kalan = await sql`select count(*)::int n from sahte.desteler where no between 900100 and 900199`;
    assert.equal(kalan[0]!.n, 4);
    const [log] = await sql`select count(*)::int n from ortak.yonetim_kaydi where tablo = 'sahte.desteler' and islem = 'DELETE' and zaman > now() - interval '1 minute'`;
    assert.ok(log!.n >= 3, "silmeler yönetim kaydında");
  } finally {
    await temizle();
    await sql`delete from sahte.desteler where gun > ${gun(1)}::date`;
    if (sakla.length) await sql`insert into sahte.desteler ${sql(sakla)} on conflict do nothing`;
  }
});
