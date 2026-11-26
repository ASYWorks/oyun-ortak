// Göç 8500 (Kulis): oyun satırı (eşitlik ikincil, 5 kademeli lig, önizleme); gizli günlük tablo (gün × tür) yalnız servis rolüne;
// Haftanın Kurulu yalnız pazartesi; açılmış gün koruması, yükleme kuralı, yönetim kaydı.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { istemci, sql, yonetici, gunlukKoru } from "./yardimci.ts";

let geriKoy: (() => Promise<void>) | undefined;
after(async () => { await geriKoy?.(); await sql.end(); });

const gun = (fark: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + fark * 864e5));
/** Yarından itibaren ilk pazartesi. */
const pazartesi = () => { for (let f = 1; ; f++) if (new Date(gun(f) + "T00:00:00Z").getUTCDay() === 1) return gun(f); };
const temizle = (gunler: string[]) => sql.begin(async (t) => { await t`set local kulis.duzeltme = 'evet'`; await t`delete from kulis.gunluk where gun = any(${gunler})`; });
geriKoy = await gunlukKoru("kulis", [gun(-1), gun(1), pazartesi()]);

const satir = (g: string, n: number, tur = "gunluk") => ({ gun: g, tur, seviye: { n }, cevap: { usta: 3 }, kural_surumu: "r1", icerik_ozeti: `h${n}` });

test("8500 kulis: oyun satırı (önizleme, eşitlik ortak (8530), 5 kademe); tablo ve uçlar istemciye kapalı", async () => {
  const [o] = await sql`select ad, ayarlar from ortak.oyunlar where id = 'kulis'`;
  assert.ok(o, "satır var");
  assert.equal(o!.ayarlar.yayin, "onizleme");
  assert.equal(o!.ayarlar.siralama.esitlik, "ortak", "göç 8530");
  assert.equal(o!.ayarlar.lig.kademeler.length, 5);
  assert.equal(o!.ayarlar.lig.en_iyi_gun, 5);
  for (const rol of ["anon", "authenticated"]) {
    await assert.rejects(sql.begin(async (t) => { await t.unsafe(`set local role ${rol}`); await t`select * from kulis.gunluk limit 1`; }), /permission denied/, rol);
  }
  assert.ok((await istemci().rpc("kulis_gunluk_oku", { p_gun: gun(0) })).error);
});

test("8500 kulis.gunluk: açılmış gün korunur; gelecek yalnız değişince; hafta yalnız pazartesi; yönetim kaydı", async () => {
  const dun = gun(-1), yarin = gun(1), pzt = pazartesi();
  await temizle([dun, yarin, pzt]);
  const sv = yonetici();
  const r1 = (await sv.rpc("kulis_gunluk_yukle", { p_satirlar: [satir(dun, 1), satir(yarin, 1), satir(pzt, 1, "hafta")], p_surum: "v1" })).data;
  assert.equal(r1.yazilan, 3);
  assert.equal(typeof r1.kalan_gun, "number");
  const r2 = (await sv.rpc("kulis_gunluk_yukle", { p_satirlar: [satir(dun, 9), satir(yarin, 1), satir(pzt, 2, "hafta")], p_surum: "v2" })).data;
  assert.equal(r2.yazilan, 1, "yalnız değişen gelecek hafta");
  assert.deepEqual((await sv.rpc("kulis_gunluk_oku", { p_gun: dun })).data.seviye, { n: 1 });
  assert.equal((await sv.rpc("kulis_gunluk_oku", { p_gun: pzt, p_tur: "hafta" })).data.icerik_ozeti, "h2");
  await assert.rejects(sql`update kulis.gunluk set cevap = '{}' where gun = ${dun} and tur = 'gunluk'`, /acilmis_gun_degisemez/);
  const salimi = new Date(pzt + "T00:00:00Z"); salimi.setUTCDate(salimi.getUTCDate() + 1);
  assert.ok((await sv.rpc("kulis_gunluk_yukle", { p_satirlar: [satir(salimi.toISOString().slice(0, 10), 1, "hafta")], p_surum: "v1" })).error, "salı hafta olamaz");
  const [k] = await sql`select count(*)::int as n from ortak.yonetim_kaydi where tablo = 'kulis.gunluk'`;
  assert.ok(k!.n >= 4);
  await temizle([dun, yarin, pzt]);
});
