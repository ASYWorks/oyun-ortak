import { after, test } from "node:test";
import assert from "node:assert/strict";
import { bellekDepo } from "../../src/kayit/index.ts";
import { hesapBaslat } from "../../src/hesap/index.ts";
import { siralamaBaslat } from "../../src/siralama/index.ts";
import { bugun, istemci, kaliciGir, kaliciKullanici, MAILPIT, ortak, rastgeleEposta, rpc, sql, yonetici, adVer } from "./yardimci.ts";

after(() => sql.end());

const yeniHesap = () => {
  const supabase = istemci();
  return hesapBaslat({ supabase, oyunId: "deneme", depo: bellekDepo() });
};

test("istemci ortak tablolara doğrudan erişemez; servis fonksiyonlarını çağıramaz", async () => {
  const h = yeniHesap();
  await h.anonimGir();
  for (const t of ["skorlar", "oyuncular", "kayitlar", "profiller", "denemeler", "lig_uyeleri", "devirler"]) {
    const { error } = await ortak(h.supabase).from(t).select("*").limit(1);
    assert.ok(error, `${t} okunabildi`);
  }
  const { error } = await ortak(h.supabase).rpc("lig_kapat");
  assert.match(error?.message ?? "", /permission denied/);
  // oyunlar tablosu (ayarlar) herkese açık
  const { data } = await ortak(istemci()).from("oyunlar").select("id").eq("id", "deneme");
  assert.equal(data?.length, 1);
});

test("oturumsuz: sıralama okunur, kişisel işler reddedilir", async () => {
  const c = istemci();
  const t = await rpc<{ toplam: number }>(c, "siralama", { p_oyun: "deneme", p_tur: "gunluk", p_donem: "2000-01-01" });
  assert.equal(t.toplam, 0);
  await assert.rejects(rpc(c, "ben", { p_oyun: "deneme" }));
});

test("anonim oturum: ben, yaş onayı, otomatik ad", async () => {
  const h = yeniHesap();
  await h.anonimGir();
  const b = await h.ben();
  assert.equal(b.anonim, true);
  assert.equal(b.ad, null);
  await h.yasOnayla();
  assert.ok((await h.ben()).yas_onay);
  const r = await h.otomatikAd();
  assert.equal(r.durum, "ok");
  const ad = (r as { ad: string }).ad;
  assert.match(ad, /^#[A-HJ-NP-Z2-9]{5}$/); // misafir adı: # + 5 karakter (15 Kasım 2026)
  // ikinci çağrı yeni ad üretmez: otomatik yol yeniden adlandırma kapısı değildir
  assert.deepEqual(await h.otomatikAd(), { durum: "ok", ad });
  // istemci otomatik yola ad metni veremez
  const { error } = await h.supabase.schema("ortak").rpc("ad_degistir", { p_oyun: "deneme", p_ad: "Kahveci1", p_otomatik: true });
  assert.ok(error);
});

test("takma ad: biçim, uygunsuz söz, Türkçe katlamalı benzersizlik, 30 gün", async () => {
  const a = yeniHesap();
  await kaliciGir(a);
  const ad = `Işık${Math.floor(Math.random() * 1e6)}`;
  assert.deepEqual(await a.adDegistir(ad), { durum: "ok", ad });
  assert.deepEqual(await a.adDegistir("Başka1"), { durum: "bekle", bekle_gun: 30 });

  const b = yeniHesap();
  await kaliciGir(b);
  assert.equal((await b.adDegistir(ad.replace("Işık", "isik"))).durum, "alinmis");
  assert.equal((await b.adDegistir(ad.replace("Işık", "I.ŞIK"))).durum, "alinmis");
  // Sondaki rakamlar harfe çevrilmez (önce "Işık156759" → "isikists" → "sikis" yanlış pozitifti)
  // Sona eklenen rastgele harf benzersizliği sağlar (rakam eklemek kuralı değiştirirdi)
  const harf = () => "abcdefghjkmnprstuvyz"[Math.floor(Math.random() * 20)]!;
  for (const iyi of ["Işık156759", "Bekçi4821", "Sis5"]) {
    const c = yeniHesap();
    await kaliciGir(c);
    const ad = `${harf()}${harf()}${harf()}${iyi}`;
    assert.equal((await c.adDegistir(ad)).durum, "ok", ad);
  }
  for (const kotu of ["S1kt1r42", "orospucocugu", "Admin", "sik", "BahisKral", "denemeci", "5iktir", "0rospu", "Go7", "Naz1", "Sik42", "Pic99"])
    assert.equal((await b.adDegistir(kotu)).durum, "uygunsuz", kotu);
  for (const yanlis of ["ab", "x".repeat(21), "iki boşluk", "123", "a<b>c", "x\ty", "_ali", "ali.", "ali__veli", "kara-kedi"])
    assert.equal((await b.adDegistir(yanlis)).durum, "bicim", yanlis);
  // yanlış pozitif olmamalı
  for (const iyi of ["Memet", "Seksen", "Sıkı_Dost"]) {
    const c = yeniHesap();
    await kaliciGir(c);
    assert.equal((await c.adDegistir(`${iyi}${Math.floor(Math.random() * 1000)}`)).durum, "ok", iyi);
  }
  // otomatik ad elle seçileni ezmez
  assert.deepEqual(await a.otomatikAd(), { durum: "ok", ad });
});

test("misafir (anonim) takma ad seçemez, bulut kaydı ve ödül yazamaz", async () => {
  const h = yeniHesap();
  await h.anonimGir();
  await assert.rejects(h.adDegistir("Misafir123"), /kalici_hesap_gerekli/);
  await assert.rejects(rpc(h.supabase, "kayit_yaz", { p_oyun: "deneme", p_veri: { a: 1 }, p_surum: 0 }), /kalici_hesap_gerekli/);
  await assert.rejects(rpc(h.supabase, "odul_kaydet", { p_oyun: "deneme", p_oduller: [{ odul: "x" }] }), /kalici_hesap_gerekli/);
});

test("ödül tavanı: oyun başına kullanıcı başına en çok 1000", async () => {
  const h = yeniHesap();
  const id = await kaliciGir(h);
  await sql`insert into ortak.oduller (oyun_id, kullanici_id, odul) select 'deneme', ${id}, 'd' || i from generate_series(1, 950) i`;
  await assert.rejects(rpc(h.supabase, "odul_kaydet", { p_oyun: "deneme", p_oduller: Array.from({ length: 51 }, (_, i) => ({ odul: `y${i}` })) }), /odul_tavan/);
  assert.equal(await rpc(h.supabase, "odul_kaydet", { p_oyun: "deneme", p_oduller: Array.from({ length: 50 }, (_, i) => ({ odul: `y${i}` })) }), 50);
});

test("bulut kaydı: iyimser kilit ve birleştirme işlevi", async () => {
  const h = yeniHesap();
  await kaliciGir(h);
  const k = h.bulutKaydi<{ seviyeler: Record<string, number> }>();
  const birlestir = (y: { seviyeler: Record<string, number> }, u: { seviyeler: Record<string, number> }) => {
    const s = { ...u.seviyeler };
    for (const [n, v] of Object.entries(y.seviyeler)) s[n] = Math.max(s[n] ?? 0, v);
    return { kayit: { seviyeler: s }, ozet: `${Object.keys(s).length} seviye` };
  };
  await k.birlestir({ seviyeler: { "1": 2 } }, birlestir);
  const r = await k.birlestir({ seviyeler: { "1": 1, "2": 3 } }, birlestir);
  assert.deepEqual(r, { kayit: { seviyeler: { "1": 2, "2": 3 } }, ozet: "2 seviye" });
  // değişmeyen kayıt yazılmaz (GC-2): sürüm artmaz
  const once = (await k.oku())!.surum;
  await k.birlestir({ seviyeler: { "2": 1 } }, birlestir);
  assert.equal((await k.oku())!.surum, once);
  // aynı sürümle iki yazımdan biri kazanır
  const s = (await k.oku())!.surum;
  const y1 = await rpc(h.supabase, "kayit_yaz", { p_oyun: "deneme", p_veri: { a: 1 }, p_surum: s });
  const y2 = await rpc(h.supabase, "kayit_yaz", { p_oyun: "deneme", p_veri: { a: 2 }, p_surum: s });
  assert.equal(y1, s + 1);
  assert.equal(y2, null);
  await assert.rejects(rpc(h.supabase, "kayit_yaz", { p_oyun: "deneme", p_veri: { x: "y".repeat(270_000) }, p_surum: s + 1 }));
});

/**
 * Misafir olarak otomatik ad oluşturur. Misafir takma ad seçemez, bulut kaydı yazamaz, günlük sıralamaya skor
 * gönderemez (15 Kasım 2026: günlük yalnız hesapla, `durum: "misafir"`). Devir yolunu sınamak için eski verideki gibi
 * bir misafir skoru (puan 10) doğrudan yazılır.
 */
async function misafirOyna() {
  const h = yeniHesap();
  const anonId = await h.anonimGir();
  const ad = ((await h.otomatikAd()) as { ad: string }).ad;
  const s = siralamaBaslat({ supabase: h.supabase, oyunId: "deneme", depo: bellekDepo() });
  const g = await s.gonder({ islem: "gunluk", gun: bugun(), kayit: [5, 5], kuralSurumu: 1 });
  assert.equal((g.veri as { durum: string }).durum, "misafir");
  await sql`insert into ortak.skorlar (oyun_id, kullanici_id, tur, donem, puan, run_id) values ('deneme', ${anonId}, 'gunluk', ${bugun()}, 10, gen_random_uuid())`;
  return { h, s, anonId, ad };
}

test("misafir → yeni kalıcı hesap: skor dahil her şey taşınır, anonim hesap silinir", async () => {
  const k = await kaliciKullanici();
  const { h, s, anonId, ad } = await misafirOyna();
  const r = await h.disGiris(() => h.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  assert.deepEqual(r, { devredilen: ["deneme"], skorlarTasindi: true });
  assert.equal((await h.ben()).ad, ad);
  const t = await s.tablo("gunluk", bugun(), { ilk: 100 });
  assert.equal(t.satirlar.find((x) => x.ben)?.puan, 10);
  assert.equal((await sql`select count(*)::int as n from auth.users where id = ${anonId}`)[0]!.n, 0);
});

test("misafir → var olan kalıcı hesap: ad ve kayıt taşınır, skor taşınmaz (en iyisini seçme hilesi)", async () => {
  const k = await kaliciKullanici();
  // kalıcı hesabın daha önceki verisi
  const eski = yeniHesap();
  await eski.disGiris(() => eski.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  await eski.ben();

  const { h, s, anonId, ad } = await misafirOyna();

  const r = await h.disGiris(() => h.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  assert.deepEqual(r, { devredilen: ["deneme"], skorlarTasindi: false });
  const ben = await h.ben();
  assert.equal(ben.anonim, false);
  assert.equal(ben.ad, ad); // kalıcı hesapta ad yoktu, misafirinki alındı
  const t = await s.tablo("gunluk", bugun(), { ilk: 100 });
  assert.equal(t.satirlar.find((x) => x.ben), undefined);
  const [{ n }] = await sql`select count(*)::int as n from auth.users where id = ${anonId}`;
  assert.equal(n, 0);
  // ödül yalnız kalıcı hesapta ve bir kez
  assert.equal(await h.baglamaOdulu(), "deneme-rozet");
  assert.equal(await h.baglamaOdulu(), null);
});

test("var olan hesabın o oyunda satırı yoksa misafirin kademesi taşınmaz, yalnız adı gelir", async () => {
  await sql`insert into ortak.oyunlar (id, ad) values ('deneme-iki', 'Deneme İki') on conflict do nothing`;
  const k = await kaliciKullanici();
  await sql`insert into ortak.oyuncular (oyun_id, kullanici_id) values ('deneme-iki', ${k.id})`; // başka oyunda izi var
  const { h, anonId, ad } = await misafirOyna();
  await sql`update ortak.oyuncular set kademe = 4, seviye_puani = 900 where kullanici_id = ${anonId}`;
  const r = await h.disGiris(() => h.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  assert.equal(r.skorlarTasindi, false);
  const ben = await h.ben();
  assert.deepEqual([ben.ad, ben.kademe, ben.seviye_puani], [ad, 0, 0]);
});

test("aynı hedefe eş zamanlı iki devir: skorları en çok biri taşır", async () => {
  const k = await kaliciKullanici();
  const a = await misafirOyna();
  const b = await misafirOyna();
  const kodA = await rpc<string>(a.h.supabase, "devir_kodu_al");
  const kodB = await rpc<string>(b.h.supabase, "devir_kodu_al");
  await a.h.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola });
  await b.h.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola });
  const sonuclar = await Promise.all([
    rpc<{ skorlar_tasindi: boolean }>(a.h.supabase, "hesap_devral", { p_kod: kodA }),
    rpc<{ skorlar_tasindi: boolean }>(b.h.supabase, "hesap_devral", { p_kod: kodB }),
  ]);
  assert.equal(sonuclar.filter((s) => s.skorlar_tasindi).length, 1);
  assert.equal((await sql`select count(*)::int as n from ortak.skorlar where kullanici_id = ${k.id}`)[0]!.n, 1);
});

test("anonim hesap ödül alamaz; devir kodu tek kullanımlık", async () => {
  const h = yeniHesap();
  await h.anonimGir();
  assert.equal(await h.baglamaOdulu(), null);
  const kod = await rpc<string>(h.supabase, "devir_kodu_al");
  const k = await kaliciKullanici();
  await h.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola });
  const ilk = await rpc(h.supabase, "hesap_devral", { p_kod: kod });
  // 8460 (D03 makbuzu): yanıt kaybolup aynı hesap yeniden çağırırsa ikinci devir olmaz, aynı sonuç döner.
  assert.deepEqual(await rpc(h.supabase, "hesap_devral", { p_kod: kod }), ilk);
  // Başka hesap aynı kodu kullanamaz.
  const b = await kaliciKullanici();
  const h2 = yeniHesap();
  await h2.supabase.auth.signInWithPassword({ email: b.eposta, password: b.parola });
  await assert.rejects(rpc(h2.supabase, "hesap_devral", { p_kod: kod }), /devir_kodu_gecersiz/);
  // kalıcı hesap devir kodu alamaz
  await assert.rejects(rpc(h.supabase, "devir_kodu_al"), /anonim_degil/);
});

test("e-posta koduyla giriş (gerçek yol, Mailpit)", async () => {
  const h = yeniHesap();
  await h.anonimGir();
  await h.ben();
  const eposta = rastgeleEposta();
  // Auth servisi şablonu açılışta uzaktan çeker; CI'da ilk denemede alamazsa varsayılan (kodsuz) şablona
  // düşebiliyor. Kodsuz ileti gelirse yeniden istenir.
  let kod: string | undefined;
  let son = "";
  const gorulen = new Set<string>();
  for (let deneme = 0; deneme < 4 && !kod; deneme++) {
    if (deneme > 0) await new Promise((r) => setTimeout(r, 3000));
    await h.epostaKoduGonder(eposta);
    for (let i = 0; i < 30; i++) {
      await new Promise((r) => setTimeout(r, 500));
      const liste = (await (await fetch(`${MAILPIT}/api/v1/messages?limit=50`)).json()) as {
        messages: { ID: string; To: { Address: string }[] }[];
      };
      const id = liste.messages.find((m) => !gorulen.has(m.ID) && m.To.some((t) => t.Address === eposta))?.ID;
      if (!id) continue;
      gorulen.add(id);
      const m = (await (await fetch(`${MAILPIT}/api/v1/message/${id}`)).json()) as { Text: string; Subject: string };
      son = `${m.Subject}: ${m.Text.slice(0, 120).replace(/\s+/g, " ")}`;
      kod = /\b(\d{6})\b/.exec(m.Text)?.[1];
      break;
    }
  }
  assert.ok(kod, `kod e-postası gelmedi; son ileti: ${son || "yok"}`);
  const r = await h.epostaKoduIleGir(eposta, kod!);
  assert.deepEqual(r, { devredilen: ["deneme"], skorlarTasindi: true });
  assert.equal((await h.kullanici())?.eposta, eposta);
});

test("silme: hesaplar oyun oyun ayrı; son oyun silinince giriş kaydı da gider", async () => {
  const k = await kaliciKullanici();
  const h = yeniHesap();
  await h.disGiris(() => h.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  await h.adDegistir(`Silinecek${Math.floor(Math.random() * 1e6)}`);
  await h.bulutKaydi().birlestir({ a: 1 }, (y) => ({ kayit: y }));
  const s = siralamaBaslat({ supabase: h.supabase, oyunId: "deneme", depo: bellekDepo() });
  await s.gonder({ islem: "gunluk", gun: bugun(), kayit: [1], kuralSurumu: 1 });
  // aynı kişi başka bir oyunda da oynuyor
  const h2 = hesapBaslat({ supabase: h.supabase, oyunId: "halka", depo: bellekDepo() });
  await h2.otomatikAd();
  const kullaniciSayisi = async () => (await sql`select count(*)::int as n from auth.users where id = ${k.id}`)[0]!.n;

  // deneme silinir: deneme verisi gider, halka ve giriş kaydı kalır; oturum kapanır
  await h.hesabiSil();
  assert.equal(await h.kullanici(), null);
  const kalan = await sql`
    select (select count(*) from ortak.skorlar where kullanici_id = ${k.id} and oyun_id = 'deneme')
         + (select count(*) from ortak.kayitlar where kullanici_id = ${k.id} and oyun_id = 'deneme')
         + (select count(*) from ortak.oyuncular where kullanici_id = ${k.id} and oyun_id = 'deneme')
         + (select count(*) from ortak.lig_uyeleri where kullanici_id = ${k.id} and oyun_id = 'deneme')
         + (select count(*) from ortak.aktif_oyuncular where kullanici_id = ${k.id} and oyun_id = 'deneme')::int as n`;
  assert.equal(Number(kalan[0]!.n), 0);
  assert.equal((await sql`select count(*)::int as n from ortak.oyuncular where kullanici_id = ${k.id} and oyun_id = 'halka'`)[0]!.n, 1);
  assert.equal(await kullaniciSayisi(), 1);

  // halka da silinir: başka oyunda veri kalmadı, giriş kaydı da gider ve kimlik hiçbir tabloda kalmaz
  const h3 = hesapBaslat({ supabase: istemci(), oyunId: "halka", depo: bellekDepo() });
  await h3.disGiris(() => h3.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  await h3.yasOnayla(); // oyundan bağımsız kayıt (yaş beyanı) hesabı tek başına tutmaz
  await h3.hesabiSil();
  assert.equal(await kullaniciSayisi(), 0);
  const izler = await sql`
    select c.table_schema || '.' || c.table_name as t
    from information_schema.columns c
    where c.table_schema = 'ortak' and c.column_name in ('kullanici_id', 'anonim_id')`;
  for (const { t } of izler) {
    const col = t === "ortak.devirler" ? "anonim_id" : "kullanici_id";
    const [{ n }] = await sql.unsafe(`select count(*)::int as n from ${t} where ${col} = $1`, [k.id]);
    assert.equal(n, 0, t);
  }
});

test("silip aynı gün yeniden açan hesap açabilir ama o gün günlük sıralamaya giremez", async () => {
  const k = await kaliciKullanici();
  const h = yeniHesap();
  await h.disGiris(() => h.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  await h.otomatikAd();
  await h.hesabiSil();
  assert.equal((await sql`select count(*)::int as n from auth.users where id = ${k.id}`)[0]!.n, 0);

  // aynı e-postayla yeni hesap: açılır, oyuncu satırı açılır
  const { data, error } = await yonetici().auth.admin.createUser({ email: k.eposta.toUpperCase(), password: k.parola, email_confirm: true });
  assert.equal(error, null);
  const yeni = data.user!.id;
  const h2 = yeniHesap();
  await h2.disGiris(() => h2.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  assert.equal((await h2.otomatikAd()).durum, "ok");
  await adVer(yeni);
  const yaz = async (tur: string, kullanici = yeni) =>
    ((await sql`select ortak.skor_yaz('deneme', ${kullanici}, ${tur}, ${bugun()}, 10, gen_random_uuid()) as r`)[0]!.r as { durum: string }).durum;
  assert.equal(await yaz("gunluk"), "prova"); // bugünün sıralamasına girmez
  assert.equal(await yaz("etkinlik"), "yeni"); // günlük dışı (etkinlik) etkilenmez
  const baska = await kaliciKullanici();
  await adVer(baska.id);
  assert.equal(await yaz("gunluk", baska.id), "yeni"); // başka kişi etkilenmez
  // dünün dönemine geç gönderilen skor da girmez
  const dun = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() - 864e5));
  assert.equal(((await sql`select ortak.skor_yaz('deneme', ${yeni}, 'gunluk', ${dun}, 10, gen_random_uuid()) as r`)[0]!.r as { durum: string }).durum, "prova");
  // istemci "tamamen sil" çağıramaz (kimlik özeti yazmadan siliyordu)
  const { error: tamamen } = await h2.supabase.schema("ortak").rpc("hesabi_sil");
  assert.ok(tamamen);
  // ertesi gün girer
  await sql`update ortak.silinen_kimlikler set silindi = now() - interval '1 day' where oyun_id = 'deneme'`;
  assert.equal(await yaz("gunluk"), "yeni");
  // 8200: dün silinen hesap, geç kabul penceresinde dünün dönemine de giremez (eski kural yalnız bugüne bakıyordu)
  assert.equal(((await sql`select ortak.skor_yaz('deneme', ${yeni}, 'gunluk', ${dun}, 10, gen_random_uuid()) as r`)[0]!.r as { durum: string }).durum, "prova");
});


test("silinen hesabın ad kilidi: yeniden açınca ad ve kilit geri gelir, ad başkasına verilmez (AD-1)", async () => {
  const k = await kaliciKullanici();
  const h = yeniHesap();
  await h.disGiris(() => h.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  const ad = `Ad${crypto.randomUUID().replace(/-/g, "").slice(0, 10)}`;
  assert.equal((await rpc<{ durum: string }>(h.supabase, "ad_degistir", { p_oyun: "deneme", p_ad: ad })).durum, "ok");
  await h.hesabiSil();

  // kilit sürerken başkası alamaz
  const b = yeniHesap();
  await kaliciGir(b);
  assert.equal((await rpc<{ durum: string }>(b.supabase, "ad_degistir", { p_oyun: "deneme", p_ad: ad })).durum, "alinmis");

  // aynı e-postayla yeniden: ad geri, kilit sürüyor
  await yonetici().auth.admin.createUser({ email: k.eposta, password: k.parola, email_confirm: true });
  const h2 = yeniHesap();
  await h2.disGiris(() => h2.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  const ben = await rpc<{ ad: string; ad_otomatik: boolean; ad_degisti: string | null }>(h2.supabase, "ben", { p_oyun: "deneme" });
  assert.equal(ben.ad, ad);
  assert.equal(ben.ad_otomatik, false);
  assert.ok(ben.ad_degisti);
  const yeniden = await rpc<{ durum: string; bekle_gun?: number }>(h2.supabase, "ad_degistir", { p_oyun: "deneme", p_ad: `${ad}x` });
  assert.equal(yeniden.durum, "bekle");
  assert.equal(yeniden.bekle_gun, 30);
  assert.equal((await sql`select count(*)::int as n from ortak.silinen_adlar where ad = ${ad}`)[0]!.n, 0);

  // kilidi bitmiş hesapta iz kalmaz
  await sql`update ortak.oyuncular set ad_degisti = now() - interval '31 days' where oyun_id = 'deneme' and ad = ${ad}`;
  await h2.hesabiSil();
  assert.equal((await sql`select count(*)::int as n from ortak.silinen_adlar where ad = ${ad}`)[0]!.n, 0);
});

test("MD-24 bulutKaydi.birlestir({ kim }): beklenen hesap değilse yazmaz, hesap_degisti fırlatır", async () => {
  const k = await kaliciKullanici();
  const h = yeniHesap();
  await h.disGiris(() => h.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  const b = h.bulutKaydi<{ a: number }>();
  await assert.rejects(b.birlestir({ a: 1 }, (y) => ({ kayit: y }), { kim: crypto.randomUUID() }), /hesap_degisti/);
  assert.equal(await b.oku(), null, "başka hesabın kaydı yazılmadı");
  const r = await b.birlestir({ a: 2 }, (y) => ({ kayit: y }), { kim: k.id });
  assert.deepEqual(r.kayit, { a: 2 }, "doğru hesapla yazar");
});

test("8440 kayit_*_hesapli: sunucu beklenen hesabı her çağrıda doğrular; eski kayit_oku/kayit_yaz aynen çalışır", async () => {
  const a = yeniHesap(), b = yeniHesap();
  const idA = await kaliciGir(a), idB = await kaliciGir(b);
  await rpc(b.supabase, "kayit_yaz", { p_oyun: "deneme", p_veri: { b: 1 }, p_surum: 0 }); // eski tüketici: imza aynı
  // A oturumu B'yi beklerse (arada hesap değişmiş gibi) okuma da yazma da reddedilir; B'nin kaydı ne okunur ne değişir.
  await assert.rejects(rpc(a.supabase, "kayit_oku_hesapli", { p_oyun: "deneme", p_kim: idB }), /hesap_degisti/);
  await assert.rejects(rpc(a.supabase, "kayit_yaz_hesapli", { p_oyun: "deneme", p_veri: { a: 9 }, p_surum: 1, p_kim: idB }), /hesap_degisti/);
  await assert.rejects(rpc(a.supabase, "kayit_oku_hesapli", { p_oyun: "deneme", p_kim: null }), /hesap_degisti/);
  assert.deepEqual((await rpc<{ veri: unknown; surum: number }>(b.supabase, "kayit_oku", { p_oyun: "deneme" })).veri, { b: 1 });
  assert.equal(await rpc(a.supabase, "kayit_oku_hesapli", { p_oyun: "deneme", p_kim: idA }), null);
  // doğru hesapta eski uygulamaya devreder: iyimser kilit ve sürüm aynı
  assert.equal(await rpc(a.supabase, "kayit_yaz_hesapli", { p_oyun: "deneme", p_veri: { a: 1 }, p_surum: 0, p_kim: idA }), 1);
  assert.equal(await rpc(a.supabase, "kayit_yaz_hesapli", { p_oyun: "deneme", p_veri: { a: 2 }, p_surum: 0, p_kim: idA }), null);
  // oturumsuz ve misafir aynı biçimde reddedilir
  await assert.rejects(rpc(istemci(), "kayit_oku_hesapli", { p_oyun: "deneme", p_kim: idA }));
  const m = yeniHesap();
  const idM = await m.anonimGir();
  await assert.rejects(rpc(m.supabase, "kayit_yaz_hesapli", { p_oyun: "deneme", p_veri: { a: 1 }, p_surum: 0, p_kim: idM }), /kalici_hesap_gerekli/);
});

test("MD-24 istemci: kim verilince doğrulamalı işlevler kullanılır, eski yola düşülmez", async () => {
  const h = yeniHesap();
  const id = await kaliciGir(h);
  const cagrilar: string[] = [];
  const asil = h.supabase.schema.bind(h.supabase);
  (h.supabase as unknown as { schema: typeof asil }).schema = ((s: string) => {
    const sc = asil(s);
    const rpcAsil = sc.rpc.bind(sc);
    return Object.assign(Object.create(sc), { rpc: (ad: string, arg?: object) => { cagrilar.push(ad); return rpcAsil(ad, arg); } });
  }) as typeof asil;
  const r = await h.bulutKaydi<{ a: number }>().birlestir({ a: 3 }, (y) => ({ kayit: y }), { kim: id });
  assert.deepEqual(r.kayit, { a: 3 });
  assert.deepEqual(cagrilar, ["kayit_oku_hesapli", "kayit_yaz_hesapli"]);
});
