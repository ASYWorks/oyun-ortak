// Göç 8200 (Koz Hesabı): oyun satırı, gizli günlük tablo yalnız servis rolüne, açılmış gün koruması, yükleme kuralı.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { istemci, kaliciKullanici, sql, yonetici } from "./yardimci.ts";

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

const girisli = async () => {
  const k = await kaliciKullanici();
  const c = istemci();
  const { error } = await c.auth.signInWithPassword({ email: k.eposta, password: k.parola });
  if (error) throw error;
  return { ...k, c };
};

test("8210 koz: lig ve silme ayarı; arkadaş kodu, ekleme, düello açma ve günlük sınır; silme", async () => {
  const [o] = await sql`select ayarlar from ortak.oyunlar where id = 'koz'`;
  assert.deepEqual(o!.ayarlar.lig.kademeler, ["Onlu", "Vale", "Kız", "Papaz", "As"]);
  assert.equal(o!.ayarlar.hesap.silme_fonksiyonu, "koz.oyuncu_verisini_sil");
  const a = await girisli(), b = await girisli();
  const kodA = (await a.c.rpc("koz_kodum")).data as string, kodB = (await b.c.rpc("koz_kodum")).data as string;
  assert.match(kodA, /^[ACDEFGHJKMNPRTUVWXY34679]{8}$/);
  assert.equal((await a.c.rpc("koz_kodum")).data, kodA, "aynı kod döner");
  assert.equal(((await a.c.rpc("koz_arkadas_ekle", { p_kod: kodA })).data as { hata: string }).hata, "kendin");
  assert.ok(((await a.c.rpc("koz_arkadas_ekle", { p_kod: kodB.toLowerCase() })).data as { tamam: boolean }).tamam);
  assert.equal(((await b.c.rpc("koz_arkadaslar")).data as unknown[]).length, 1, "iki yönlü");
  const yon = yonetici();
  await yon.rpc("koz_duello_havuz_yukle", { p_satirlar: Array.from({ length: 20 }, (_, i) => ({ id: `t-${a.id}-${i}`, kayit: { i } })) });
  for (let i = 0; i < 3; i++) assert.ifError((await a.c.rpc("koz_duello_ac", { p_kod: kodB, p_el: 3 })).error);
  assert.match((await a.c.rpc("koz_duello_ac", { p_kod: kodB, p_el: 3 })).error?.message ?? "", /gunluk_sinir/);
  const d = (await b.c.rpc("koz_duellolar")).data as { el: number; karsi: unknown }[];
  assert.equal(d.length, 3); assert.equal(d[0]!.el, 3);
  assert.ok(!JSON.stringify(d).includes(a.id), "kimlik dönmez");
  const misafir = istemci(); await misafir.auth.signInAnonymously();
  assert.match((await misafir.rpc("koz_kodum")).error?.message ?? "", /kalici_hesap_gerekli/);
  await sql`select koz.oyuncu_verisini_sil(${a.id})`;
  const [{ n }] = await sql`select (select count(*) from koz.arkadaslik where kullanici = ${a.id} or arkadas = ${a.id}) + (select count(*) from koz.duello where acan = ${a.id}) as n`;
  assert.equal(Number(n), 0);
  await sql`delete from koz.duello_havuz where id like ${"t-" + a.id + "%"}`;
});

test("8220+8230 koz: arkadaş tutamaçla silinir (adsız da), iki yönlü, kod yenileyince eski kod geçersiz, paralel düello açma sınırı aşmaz", async () => {
  const a = await girisli(), b = await girisli();
  const kodB = (await b.c.rpc("koz_kodum")).data as string;
  await a.c.rpc("koz_arkadas_ekle", { p_kod: kodB });
  const adB = `kb${b.id.slice(0, 8)}`;
  await sql`insert into ortak.oyuncular (oyun_id, kullanici_id, ad, ad_otomatik) values ('koz', ${b.id}, ${adB}, false)
            on conflict (oyun_id, kullanici_id) do update set ad = excluded.ad`;
  await yonetici().rpc("koz_duello_havuz_yukle", { p_satirlar: Array.from({ length: 30 }, (_, i) => ({ id: `p-${a.id}-${i}`, kayit: { i } })) });
  const sonuc = await Promise.all(Array.from({ length: 6 }, () => a.c.rpc("koz_duello_ac", { p_kod: kodB, p_el: 3 })));
  assert.equal(sonuc.filter((x) => !x.error).length, 3, "paralel istekte de en çok 3");
  const liste = (await a.c.rpc("koz_arkadaslar")).data as { tutamac: string; ad: string }[];
  assert.equal(liste[0]!.ad, adB);
  assert.ok(((await a.c.rpc("koz_arkadas_sil", { p_tutamac: liste[0]!.tutamac })).data as { tamam: boolean }).tamam);
  assert.equal(((await b.c.rpc("koz_arkadaslar")).data as unknown[]).length, 0, "iki yön silindi");
  const yeni = (await b.c.rpc("koz_kod_yenile")).data as string;
  assert.notEqual(yeni, kodB);
  assert.equal(((await a.c.rpc("koz_arkadas_ekle", { p_kod: kodB })).data as { hata: string }).hata, "kod_yok");
  await sql`delete from koz.duello where acan = ${a.id}`;
  await sql`delete from koz.duello_havuz where id like ${"p-" + a.id + "%"}`;
});
