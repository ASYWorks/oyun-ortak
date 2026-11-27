// Göç 8570 (ORT-ARK, BG-12/RZ-9): arkadaş tablosu, etkinlik eşleşmesi, eşitlerin terfisi, alt oyun ligi, para tarafsızlığı.
import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { bellekDepo } from "../../src/kayit/index.ts";
import { hesapBaslat } from "../../src/hesap/index.ts";
import { siralamaBaslat } from "../../src/siralama/index.ts";
import { istemci, kaliciGir, oyunuTemizle, sql } from "./yardimci.ts";

before(() => oyunuTemizle());
after(() => sql.end());

const [{ bu, gecen }] = await sql`select ortak.iso_hafta(ortak.bugun())::text as bu, (ortak.iso_hafta(ortak.bugun()) - 7)::text as gecen`;
const gunu = (hafta: string, n: number) => {
  const d = new Date(`${hafta}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};
async function sahteOyuncu(kademe = 0) {
  const [{ id }] = await sql`insert into auth.users (id, aud, role, is_anonymous) values (gen_random_uuid(), 'authenticated', 'authenticated', false) returning id`;
  const ad = `A${crypto.randomUUID().replace(/-/g, "").slice(0, 12)}`;
  await sql`insert into ortak.oyuncular (oyun_id, kullanici_id, kademe, ad, ad_anahtari, ad_otomatik) values ('deneme', ${id}, ${kademe}, ${ad}, ortak.ad_anahtari(${ad}), false)`;
  return id as string;
}
const skor = (id: string, gun: string, lig: number, tur = "gunluk") =>
  sql`select ortak.skor_yaz('deneme', ${id}, ${tur}, ${gun}, ${lig * 10}, gen_random_uuid(), 1, ${lig})`;
async function oyuncuGir(ad: string) {
  const c = istemci();
  const h = hesapBaslat({ supabase: c, oyunId: "deneme", depo: bellekDepo() });
  const id = await kaliciGir(h);
  await h.adDegistir(`${ad}${Math.floor(Math.random() * 1e6)}`);
  return { id, s: siralamaBaslat({ supabase: c, oyunId: "deneme", depo: bellekDepo() }) };
}

test("8570 arkadaş: kodla karşılıklı ekleme, tablo yalnız ben + arkadaşlar, çıkarma iki yönden", async () => {
  const a = await oyuncuGir("Ark");
  const b = await oyuncuGir("Bar");
  const yabanci = await sahteOyuncu();
  const kod = await a.s.arkadasKodum();
  assert.match(kod, /^[A-HJ-NP-Z2-9]{6}$/);
  assert.equal(await a.s.arkadasKodum(), kod, "kod kalıcı");
  await assert.rejects(a.s.arkadasEkle(kod), /kendi_kodun/);
  await assert.rejects(b.s.arkadasEkle("ZZZZZZ"), /kod_yok/);
  const eklenen = await b.s.arkadasEkle(kod.toLowerCase());
  assert.ok(eklenen.profil);

  const gun = gunu(bu, 0);
  await skor(a.id, gun, 3);
  await skor(b.id, gun, 7);
  await skor(yabanci, gun, 9);
  const t = await a.s.arkadasTablosu("gunluk", gun);
  assert.deepEqual(t.satirlar.map((x) => [x.sira, Number(x.puan), x.ben]), [[1, 70, false], [2, 30, true]], "yabancı yok, karşılıklı");
  const tb = await b.s.arkadasTablosu("gunluk", gun);
  assert.equal(tb.satirlar.length, 2);
  const hafta = await a.s.arkadasTablosu("hafta", bu);
  assert.deepEqual(hafta.satirlar.map((x) => Number(x.puan)), [7, 3], "haftalık lig puanı");

  await b.s.arkadasCikar(t.satirlar.find((x) => x.ben)!.profil!);
  assert.equal((await a.s.arkadasTablosu("gunluk", gun)).satirlar.length, 1, "iki yönden silindi");
});

test("8570 arkadaş: misafir kod alamaz; oyun verisi silinince arkadaşlık gider", async () => {
  const m = hesapBaslat({ supabase: istemci(), oyunId: "deneme", depo: bellekDepo() });
  await m.anonimGir();
  await assert.rejects(siralamaBaslat({ supabase: m.supabase, oyunId: "deneme", depo: bellekDepo() }).arkadasKodum(), /hesap_gerekli/);
  const a = await sahteOyuncu();
  const b = await sahteOyuncu();
  await sql`insert into ortak.arkadasliklar (oyun_id, kullanici_id, arkadas_id) values ('deneme', ${a}, ${b}), ('deneme', ${b}, ${a})`;
  await sql`delete from ortak.oyuncular where oyun_id = 'deneme' and kullanici_id = ${a}`;
  assert.equal((await sql`select count(*)::int n from ortak.arkadasliklar where kullanici_id = ${b} or arkadas_id = ${b}`)[0]!.n, 0);
});

test("8570 lig: benzer etkinlik ayrı grup (önceki 7 günde 0–2 / 3–5 / 6–7 gün); kapatılabilir", async () => {
  const az = await sahteOyuncu(3);
  const cok = await sahteOyuncu(3);
  for (let i = 0; i < 7; i++) await skor(cok, gunu(gecen, i), 1);
  await skor(az, gunu(gecen, 0), 1);
  await skor(az, gunu(bu, 0), 2);
  await skor(cok, gunu(bu, 0), 2);
  const g = await sql`select u.kullanici_id, gr.etkinlik from ortak.lig_uyeleri u join ortak.lig_gruplari gr on gr.id = u.grup_id where u.hafta = ${bu} and u.kullanici_id in ${sql([az, cok])}`;
  const e = Object.fromEntries(g.map((r) => [r.kullanici_id, r.etkinlik]));
  assert.deepEqual([e[az], e[cok]], [0, 2]);

  await sql`update ortak.oyunlar set ayarlar = jsonb_set(ayarlar, '{lig,etkinlik_esles}', 'false') where id = 'deneme'`;
  try {
    const x = await sahteOyuncu(4);
    for (let i = 0; i < 7; i++) await skor(x, gunu(gecen, i), 1);
    await skor(x, gunu(bu, 0), 2);
    assert.equal((await sql`select gr.etkinlik from ortak.lig_uyeleri u join ortak.lig_gruplari gr on gr.id = u.grup_id where u.hafta = ${bu} and u.kullanici_id = ${x}`)[0]!.etkinlik, 0);
  } finally {
    await sql`update ortak.oyunlar set ayarlar = ayarlar #- '{lig,etkinlik_esles}' where id = 'deneme'`;
  }
});

test("8570 lig: terfi sınırında eşit puanlıların hepsi çıkar (rank)", async () => {
  const idler: string[] = [];
  // 10 oyuncu, çıkış %20 = ilk 2; 2., 3. ve 4. eşit (puan 9) → dördü de çıkar
  const puanlar = [10, 9, 9, 9, 5, 4, 3, 2, 1, 1];
  for (const p of puanlar) { const id = await sahteOyuncu(1); idler.push(id); }
  // aynı grup: gecen haftaya elle ata (etkinlik eşleşmesinden bağımsız)
  const [{ gid }] = await sql`insert into ortak.lig_gruplari (oyun_id, hafta, kademe) values ('deneme', ${gecen}, 1) returning id as gid`;
  for (const [i, id] of idler.entries()) {
    await sql`insert into ortak.lig_uyeleri (grup_id, oyun_id, hafta, kullanici_id) values (${gid}, 'deneme', ${gecen}, ${id})`;
    await skor(id, gunu(gecen, 1), puanlar[i]!);
  }
  await sql`select ortak.lig_kapat()`;
  const s = await sql`select kullanici_id, sonuc from ortak.lig_uyeleri where grup_id = ${gid}`;
  const sonuc = Object.fromEntries(s.map((r) => [r.kullanici_id, r.sonuc]));
  assert.deepEqual(idler.map((id) => sonuc[id]), ["cikti", "cikti", "cikti", "cikti", "kaldi", "kaldi", "kaldi", "kaldi", "kaldi", "kaldi"].map((x, i) => i >= 8 ? "indi" : x));
});

test("8570 alt oyun ligi: aynı grup, yalnız o alt oyunun Keşif/kipsiz skorları; Yarış girmez; biçim denetimi", async () => {
  const ben = await oyuncuGir("Alt");
  const rakip = await sahteOyuncu(0);
  const g0 = gunu(bu, 0);
  await skor(ben.id, g0, 5);
  await skor(rakip, g0, 5);
  await skor(ben.id, `${g0}:kasa:kesif`, 2, "alt");
  await skor(ben.id, `${g0}:kasa:yaris`, 50, "alt");
  await skor(rakip, `${g0}:kasa`, 4, "alt");
  await skor(rakip, `${g0}:boru`, 90, "alt");
  await assert.rejects(skor(ben.id, `${g0}:Kasa!`, 1, "alt"), /skorlar_alt_donem/);

  const genel = await ben.s.lig();
  const alt = await ben.s.lig({ alt: "kasa" });
  assert.equal(alt.alt, "kasa");
  assert.equal(alt.hafta, genel.hafta);
  const p = Object.fromEntries(alt.uyeler.map((u) => [u.ben ? "ben" : "o", Number(u.puan)]));
  if (alt.uyeler.length === 2) assert.deepEqual(p, { o: 4, ben: 2 }, "Yarış ve başka alt oyun girmez");
  else assert.equal(p.ben, 2);
  assert.deepEqual((await ben.s.tablo("alt", `${g0}:kasa:kesif`)).satirlar.map((x) => Number(x.puan)), [20]);
});

test("8570 para tarafsızlığı: hak sahibi ve olmayan aynı skorda aynı lig, arkadaş ve sıralama sonucu", async () => {
  const a = await oyuncuGir("Para");
  const b = await oyuncuGir("Parasiz");
  await sql`insert into ortak.haklar (kullanici_id, oyun_id, hak, durum, kaynak) values (${a.id}, 'deneme', 'tam', 'aktif', 'elle') on conflict do nothing`;
  await b.s.arkadasEkle(await a.s.arkadasKodum());
  const g = gunu(bu, 1);
  await skor(a.id, g, 6);
  await skor(b.id, g, 6);
  const t = await a.s.arkadasTablosu("gunluk", g);
  assert.deepEqual(t.satirlar.map((x) => x.sira), [1, 1], "eşit puan eşit sıra");
  const ta = (await a.s.tablo("gunluk", g)).ben;
  const tb = (await b.s.tablo("gunluk", g)).ben;
  assert.equal(ta!.sira, tb!.sira);
  const la = (await a.s.lig()).uyeler.find((u) => u.ben)!;
  const lb = (await b.s.lig()).uyeler.find((u) => u.ben)!;
  assert.equal(Number(la.puan), Number(lb.puan));
});
