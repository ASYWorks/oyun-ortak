// Göç 8410 (SM-5): Sahte Masası vaka bazında karar dağılımı. Açıklama ekranındaki "oyuncuların yüzde kaçı doğru karar verdi"
// satırı için: geçmiş bir günün bitmiş günlük denemelerinden her vaka için seçim sayıları. Herkese açık, kişisel veri yok;
// bugün ve sonrası için boş (sızıntı yok), 20'den az bitmiş deneme varsa boş.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { istemci, kaliciKullanici, sql } from "./yardimci.ts";

const gun = (fark: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() + fark * 864e5));
const ESKI = gun(-500), YENI = gun(-501); // gerçek günlerle çakışmasın
const kullanicilar: string[] = [];
after(async () => {
  // Yalnız bu testin kullanıcıları silinir; denemeleri onlarla gider (ÖG-53: oyunların yerel verisine dokunulmaz).
  if (kullanicilar.length) await sql`delete from auth.users where id in ${sql(kullanicilar)}`;
  await sql.end();
});

const karar = (vaka: number, secim: string) => ({ vaka, secim, dokunulan: [] });
async function deneme(anahtar: string, kararlar: unknown[], bitti = true) {
  const k = await kaliciKullanici();
  kullanicilar.push(k.id);
  await sql`insert into ortak.denemeler (oyun_id, kullanici_id, anahtar, sira, durum, bitti)
            values ('sahte', ${k.id}, ${anahtar}, ${kararlar.length}, ${sql.json({ kararlar })}, ${bitti})`;
}

test("8410 sahte_vaka_dagilim: geçmiş gün, en az 20 bitmiş deneme; bugün boş; yalnız sayılar", async () => {
  const a = istemci();
  // ESKI: 20 bitmiş deneme. Vaka 0: 15 sahte, 5 gercek; vaka 1: hepsi dogrula. Bir de bitmemiş deneme (sayılmaz).
  for (let i = 0; i < 20; i++) await deneme(`gunluk:${ESKI}`, [karar(0, i < 15 ? "sahte" : "gercek"), karar(1, "dogrula")]);
  await deneme(`gunluk:${ESKI}`, [karar(0, "gercek")], false);
  // YENI: 19 deneme, eşiğin altında.
  for (let i = 0; i < 19; i++) await deneme(`gunluk:${YENI}`, [karar(0, "sahte")]);
  // Bugün: sızıntı olmasın diye boş.
  for (let i = 0; i < 20; i++) await deneme(`gunluk:${gun(0)}`, [karar(0, "sahte")]);

  const { data, error } = await a.rpc("sahte_vaka_dagilim", { p_gun: ESKI });
  assert.ifError(error);
  assert.deepEqual(data, [
    { vaka: 0, sahte: 15, gercek: 5, dogrula: 0 },
    { vaka: 1, sahte: 0, gercek: 0, dogrula: 20 },
  ]);
  assert.deepEqual((await a.rpc("sahte_vaka_dagilim", { p_gun: YENI })).data, [], "20'den az deneme: boş");
  assert.deepEqual((await a.rpc("sahte_vaka_dagilim", { p_gun: gun(0) })).data, [], "bugün: boş");
  assert.deepEqual((await a.rpc("sahte_vaka_dagilim", { p_gun: gun(1) })).data, [], "yarın: boş");
  // 8425: dün ancak bölüm açılınca (03:00'ten sonra) döner; geç kabul penceresinde cevap sızmasın.
  for (let i = 0; i < 20; i++) await deneme(`gunluk:${gun(-1)}`, [karar(0, "sahte")]);
  const [{ acik }] = await sql`select sahte.bolum_acik(${gun(-1)}::date) as acik`;
  const dun = (await a.rpc("sahte_vaka_dagilim", { p_gun: gun(-1) })).data as unknown[];
  assert.equal(dun.length > 0, acik, "dün yalnız bolum_acik ise döner");
  const [{ sahteSaat }] = await sql`select extract(hour from now() at time zone 'Europe/Istanbul')::int as "sahteSaat"`;
  assert.equal(acik, sahteSaat >= 3);
});
