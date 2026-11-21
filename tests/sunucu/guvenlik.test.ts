// Güvenlik regresyonları (19 Kasım, performans değişikliklerinin güvenlik kontrolü). Gerçek kullanıcı oturumlarıyla HTTP
// (PostgREST + RLS + Edge) üzerinden: A, B'nin verisine erişemez; misafir ve girişsiz kapalı uçlara giremez; yönetim
// işlevleri istemciye kapalı; skor tekrarı, eşzamanlı gönderim ve başkasının gönderim kimliği tek skor üretir.
import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { bugun, fonksiyon, istemci, kaliciKullanici, oyunuTemizle, sql } from "./yardimci.ts";

after(() => sql.end());
before(() => oyunuTemizle());

/** Kalıcı hesapla girmiş istemci ve kullanıcı kimliği; adı seçilmiş (sıralamaya girebilir). */
async function oyuncu(): Promise<{ c: SupabaseClient; id: string }> {
  const k = await kaliciKullanici();
  const c = istemci();
  const { error } = await c.auth.signInWithPassword({ email: k.eposta, password: k.parola });
  if (error) throw error;
  const ad = `g${crypto.randomUUID().replace(/-/g, "").slice(0, 10)}`;
  const r = await c.schema("ortak").rpc("ad_degistir", { p_oyun: "deneme", p_ad: ad });
  assert.equal(r.data?.durum, "ok", JSON.stringify(r));
  return { c, id: k.id };
}
async function misafir(): Promise<SupabaseClient> {
  const c = istemci();
  const { error } = await c.auth.signInAnonymously();
  if (error) throw error;
  return c;
}
const reddedildi = (e: { message?: string } | null) => !!e && /permission denied|not find|does not exist|JWT|giris_gerekli|kalici_hesap_gerekli|misafir|hesap_gerekli/i.test(e.message ?? "");

const OZEL_TABLOLAR = ["skorlar", "kayitlar", "oyuncular", "oduller", "denemeler", "haklar", "hiz_sinirlari", "devirler",
  "sikayetler", "bildirim_anahtarlari", "kurulum_gunluk", "lig_uyeleri", "lig_gruplari", "profiller", "silinen_adlar"];
const YONETIM = ["skor_yaz", "siralama_odulu_ver", "lig_kapat", "kullanici_sirasi", "nabiz_isle", "deneme_al", "deneme_ilerlet",
  "hiz_siniri", "gun_toplami_yaz", "lig_ata", "lig_puani_guncelle", "odeme_olayi", "hak_aktar", "sira_listesi",
  "istek_siniri", "skor_sirasi", "oyuncu_sirasi"];

test("A, B'nin kaydını, ödülünü, hakkını okuyamaz ve değiştiremez", async () => {
  const a = await oyuncu(), b = await oyuncu();
  assert.equal((await a.c.schema("ortak").rpc("kayit_yaz", { p_oyun: "deneme", p_veri: { gizli: "A" }, p_surum: 0 })).error, null);
  assert.equal((await a.c.schema("ortak").rpc("odul_kaydet", { p_oyun: "deneme", p_oduller: [{ odul: "rozet-a" }] })).error, null);
  const bk = await b.c.schema("ortak").rpc("kayit_oku", { p_oyun: "deneme" });
  assert.equal(bk.data, null, "B, A'nın kaydını görmez");
  // B'nin yazımı yalnız kendi satırına gider; A'nınki değişmez
  await b.c.schema("ortak").rpc("kayit_yaz", { p_oyun: "deneme", p_veri: { gizli: "B" }, p_surum: 1 });
  assert.deepEqual((await a.c.schema("ortak").rpc("kayit_oku", { p_oyun: "deneme" })).data?.veri, { gizli: "A" });
  assert.deepEqual((await b.c.schema("ortak").rpc("odullerim", { p_oyun: "deneme" })).data, []);
  assert.deepEqual((await b.c.schema("ortak").rpc("haklarim", { p_oyun: "deneme" })).data, []);
});

test("doğrudan tablo erişimi: girişsiz, misafir ve girişli kimse özel ortak tablolarını okuyamaz/yazamaz", async () => {
  const roller: [string, SupabaseClient][] = [["girişsiz", istemci()], ["misafir", await misafir()], ["girişli", (await oyuncu()).c]];
  for (const [rol, c] of roller) {
    for (const t of OZEL_TABLOLAR) {
      const o = await c.schema("ortak").from(t).select("*").limit(1);
      assert.ok(reddedildi(o.error), `${rol} ${t} okuma: ${JSON.stringify(o)}`);
      const y = await c.schema("ortak").from(t).insert({});
      assert.ok(reddedildi(y.error), `${rol} ${t} yazma: ${JSON.stringify(y.error)}`);
    }
  }
});

test("yönetim/iç işlevler girişsiz, misafir ve girişliye kapalı", async () => {
  const roller: [string, SupabaseClient][] = [["girişsiz", istemci()], ["misafir", await misafir()], ["girişli", (await oyuncu()).c]];
  for (const [rol, c] of roller)
    for (const f of YONETIM) {
      const { error } = await c.schema("ortak").rpc(f, {});
      assert.ok(reddedildi(error), `${rol} ${f}: ${error?.message}`);
    }
});

test("girişsiz kalıcı hesap ister: kayıt, ödül, nabız, lig reddedilir", async () => {
  const c = istemci();
  for (const [f, a] of [["kayit_oku", { p_oyun: "deneme" }], ["kayit_yaz", { p_oyun: "deneme", p_veri: {}, p_surum: 0 }],
    ["odul_kaydet", { p_oyun: "deneme", p_oduller: [] }], ["nabiz", { p_oyun: "deneme", p_anahtar: "x" }],
    ["lig_durumu", { p_oyun: "deneme" }], ["profil_ayari", { p_oyun: "deneme", p_gizli: true }]] as const) {
    const { error } = await c.schema("ortak").rpc(f, a);
    assert.ok(reddedildi(error), `${f}: ${error?.message}`);
  }
  const m = await misafir();
  assert.ok(reddedildi((await m.schema("ortak").rpc("kayit_yaz", { p_oyun: "deneme", p_veri: {}, p_surum: 0 })).error));
  assert.ok(reddedildi((await m.schema("ortak").rpc("odul_kaydet", { p_oyun: "deneme", p_oduller: [] })).error));
});

test("istemci sunucu ödülü (sira:) yazamaz; profilde başkası istemci rozetini görmez; gizli profil yalnız ad", async () => {
  const a = await oyuncu(), b = await oyuncu();
  const yasak = await a.c.schema("ortak").rpc("odul_kaydet", { p_oyun: "deneme", p_oduller: [{ odul: "sira:sahte" }] });
  assert.match(yasak.error?.message ?? "", /odul_yasak/);
  await a.c.schema("ortak").rpc("odul_kaydet", { p_oyun: "deneme", p_oduller: [{ odul: "rozet-sahte-365" }] });
  await sql`insert into ortak.oduller (oyun_id, kullanici_id, odul, kaynak) values ('deneme', ${a.id}, 'sira:gercek', 'test')`;
  const [{ profil_id }] = await sql`select profil_id from ortak.oyuncular where oyun_id = 'deneme' and kullanici_id = ${a.id}`;
  const goren = (await b.c.schema("ortak").rpc("profil", { p_oyun: "deneme", p_profil: profil_id })).data;
  assert.deepEqual(goren.oduller.map((o: { odul: string }) => o.odul), ["sira:gercek"], "başkası yalnız sunucu ödülünü görür");
  const kendi = (await a.c.schema("ortak").rpc("profil", { p_oyun: "deneme", p_profil: profil_id })).data;
  assert.ok(kendi.oduller.some((o: { odul: string }) => o.odul === "rozet-sahte-365"), "sahibi kendi rozetini görür");
  // profil yanıtında kullanıcı kimliği ve e-posta yok
  const metin = JSON.stringify(goren);
  assert.ok(!metin.includes(a.id) && !metin.includes("@"), metin);
  assert.deepEqual(Object.keys(goren).sort(), ["ad", "ben", "desen", "etkinlik", "gizli", "gunluk", "kademe", "kademe_adi", "katilim", "lig", "oduller"]);
  await a.c.schema("ortak").rpc("profil_ayari", { p_oyun: "deneme", p_gizli: true });
  assert.deepEqual(Object.keys((await b.c.schema("ortak").rpc("profil", { p_oyun: "deneme", p_profil: profil_id })).data).sort(), ["ad", "gizli"]);
  // B, A'nın ayarını değiştiremez (profil_ayari yalnız kendi satırı)
  await b.c.schema("ortak").rpc("profil_ayari", { p_oyun: "deneme", p_gizli: false });
  assert.equal((await sql`select profil_gizli from ortak.oyuncular where oyun_id = 'deneme' and kullanici_id = ${a.id}`)[0]!.profil_gizli, true);
});

test("sıralama yanıtı yalnız yayımlanacak alanları taşır (kimlik, e-posta yok)", async () => {
  const a = await oyuncu();
  await sql`insert into ortak.skorlar (oyun_id, kullanici_id, tur, donem, puan, run_id) values ('deneme', ${a.id}, 'gunluk', ${bugun()}, 5, gen_random_uuid())`;
  const t = (await istemci().schema("ortak").rpc("siralama", { p_oyun: "deneme", p_tur: "gunluk", p_donem: bugun(), p_ilk: 100 })).data;
  const satir = t.satirlar.find((s: { puan: number }) => s.puan === 5);
  assert.deepEqual(Object.keys(satir).sort(), ["ad", "ben", "ikincil", "profil", "puan", "sira"]);
  assert.ok(!JSON.stringify(t).includes(a.id));
});

test("skor: aynı runId eşzamanlı 5 kez ve farklı runId'lerle eşzamanlı 5 kez → tek skor; başkasının runId'si kullanılamaz", async () => {
  const a = await oyuncu(), b = await oyuncu();
  const gonder = (c: SupabaseClient, runId: string, kayit = [9, 9, 9]) =>
    fonksiyon(c, "dogrula-deneme", { islem: "gunluk", gun: bugun(), kayit, kuralSurumu: 1, runId });
  const ayni = crypto.randomUUID();
  const r1 = await Promise.all(Array.from({ length: 5 }, () => gonder(a.c, ayni)));
  assert.ok(r1.every((r) => r.durum === 200), JSON.stringify(r1.map((r) => r.durum)));
  const farkli = await Promise.all(Array.from({ length: 5 }, () => gonder(a.c, crypto.randomUUID(), [1])));
  assert.ok(farkli.every((r) => r.durum === 200));
  const skorlar = await sql`select puan from ortak.skorlar where oyun_id = 'deneme' and kullanici_id = ${a.id}`;
  assert.deepEqual(skorlar.map((s) => Number(s.puan)), [27], "ilk gönderim resmî, sonrakiler prova");
  // B, A'nın runId'siyle gönderirse A'nın skoruna 'tekrar' almaz; reddedilir ve skor yazılmaz
  const cal = await gonder(b.c, ayni);
  assert.notEqual(cal.veri?.durum, "tekrar", JSON.stringify(cal.veri));
  assert.equal((await sql`select count(*)::int as n from ortak.skorlar where oyun_id = 'deneme' and kullanici_id = ${b.id}`)[0]!.n, 0);
});

test("kapanmış güne gönderim reddedilir (sunucu saati esas)", async () => {
  const a = await oyuncu();
  const eski = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(Date.now() - 3 * 86_400_000));
  const r = await fonksiyon(a.c, "dogrula-deneme", { islem: "gunluk", gun: eski, kayit: [9], kuralSurumu: 1, runId: crypto.randomUUID() });
  assert.equal(r.durum, 409);
});

test("hız sınırları: kayıt yazma dakikada 30, sıralama kullanıcı başına sınırlı", async () => {
  const a = await oyuncu();
  let son: { error: { message: string } | null } = { error: null };
  // Sınır sabit dakika penceresinde: döngü pencere sınırına denk gelebilir, en çok iki pencere boyu denenir.
  for (let i = 0; i <= 61 && !son.error; i++) son = await a.c.schema("ortak").rpc("kayit_yaz", { p_oyun: "deneme", p_veri: { i }, p_surum: -1 });
  assert.match(son.error?.message ?? "", /cok_istek/);
  let s: { error: { message: string } | null } = { error: null };
  for (let i = 0; i <= 241 && !s.error; i++) s = await a.c.schema("ortak").rpc("siralama", { p_oyun: "deneme", p_tur: "gunluk", p_donem: bugun() });
  assert.match(s.error?.message ?? "", /cok_istek/, "sıralama sınırsız çağrılamaz");
});

test("Sticky sıralaması: istemcinin verdiği dönem başlangıcı yok sayılır (6000), girişsiz sınırsız çağrılamaz (5900)", async () => {
  const c = istemci();
  const [{ id }] = await sql`insert into auth.users (id, aud, role, email) values (gen_random_uuid(), 'authenticated', 'authenticated', ${`st${Date.now()}@test.local`}) returning id`;
  await sql`insert into ortak.oyuncular (oyun_id, kullanici_id, ad, ad_anahtari) values ('sticky', ${id}, ${"eski" + Date.now()}, ${"eski" + Date.now()})`;
  // dönem başlangıcından eski 3 oyun: istemci p_baslangic'i geriye çekse de gün sıralamasına girmez
  for (let i = 0; i < 3; i++) await sql`insert into sticky.rating_log (user_id, delta, at) values (${id}, 10, now() - interval '20 days')`;
  const eski = (await c.schema("sticky").rpc("siralama", { p_donem: "gun", p_baslangic: "2000-01-01T00:00:00Z" })).data;
  assert.ok(!eski.satirlar.some((s: { ad: string }) => s.ad.startsWith("eski")), JSON.stringify(eski));
  await sql`delete from auth.users where id = ${id}`;
  let s: { error: { message: string } | null } = { error: null };
  for (let i = 0; i <= 241 && !s.error; i++) s = await c.schema("sticky").rpc("siralama", { p_donem: "gun" });
  assert.match(s.error?.message ?? "", /cok_istek/);
  // yerelde IP başlığı yok: bütün girişsizler aynı anahtarı paylaşır, sonraki testler etkilenmesin
  await sql`delete from ortak.hiz_sinirlari where anahtar like 'sticky-siralama:%'`;
});

test("Beat Greedy: B, A'nın denemelerini okuyamaz; lig doğrudan güncellenemez", async () => {
  const a = await oyuncu(), b = await oyuncu();
  await sql`insert into sezgi.profiles (id, username) values (${a.id}, ${"ga" + Date.now()}) on conflict do nothing`;
  const o = await b.c.schema("sezgi").from("attempts").select("*").eq("user_id", a.id);
  assert.deepEqual(o.data ?? [], []);
  const g = await b.c.schema("sezgi").from("leagues").update({ name: "x" }).neq("name", "");
  assert.ok(reddedildi(g.error), JSON.stringify(g.error));
});

test("SECURITY DEFINER işlevlerin hepsinde search_path sabit", async () => {
  const r = await sql`select n.nspname || '.' || p.proname as f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where p.prosecdef and n.nspname in ('ortak', 'halka', 'sezgi', 'sticky', 'public')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')`;
  assert.deepEqual(r.map((x) => x.f), []);
});

test("servis anahtarı istemci yollarına sızmaz: anon anahtarla servis rolü işlemi yapılamaz", async () => {
  const c = createClient(process.env.SUPABASE_URL ?? "http://127.0.0.1:55321", "gecersiz", { auth: { persistSession: false } });
  const { error } = await c.schema("ortak").from("skorlar").select("*").limit(1);
  assert.ok(error);
});

test("servis rolüne özel yeni işlevler istemciye kapalı (6400)", async () => {
  for (const [f, rol] of [["public.halka_gonderim_verisi(text, text, text, uuid)", "anon"], ["public.halka_gonderim_verisi(text, text, text, uuid)", "authenticated"],
    ["ortak.istek_siniri(text, integer, text, integer)", "anon"], ["ortak.istek_siniri(text, integer, text, integer)", "authenticated"]] as const) {
    const [{ v }] = await sql`select has_function_privilege(${rol}, ${f}, 'execute') as v`;
    assert.equal(v, false, `${rol} ${f}`);
  }
  // skor_yaz yeni ve tekrar yanıtında sıra döner (gönderimde ayrı kullanici_sirasi isteği yok)
  const a = await oyuncu();
  const runId = crypto.randomUUID();
  const r1 = await fonksiyon(a.c, "dogrula-deneme", { islem: "gunluk", gun: bugun(), kayit: [5], kuralSurumu: 1, runId });
  const r2 = await fonksiyon(a.c, "dogrula-deneme", { islem: "gunluk", gun: bugun(), kayit: [5], kuralSurumu: 1, runId });
  assert.equal(r1.veri?.durum, "yeni");
  assert.equal(typeof r1.veri?.sira?.sira, "number", JSON.stringify(r1.veri));
  assert.equal(r2.veri?.durum, "tekrar");
  assert.equal(r2.veri?.sira?.sira, r1.veri?.sira?.sira);
});

test("7300: profil deseni yalnız kazanılan ödül; hesap bağlama ödülü istemciden yazılamaz", async () => {
  const a = await oyuncu();
  const r = (p: Record<string, unknown>) => a.c.schema("ortak").rpc("profil_ayari", { p_oyun: "deneme", ...p });
  await sql`insert into ortak.oyuncular (oyun_id, kullanici_id) values ('deneme', ${a.id}) on conflict do nothing`;
  assert.match((await r({ p_desen: "desen-kazanilmamis" })).error?.message ?? "", /desen_yok/, "kazanılmamış desen ret");
  assert.equal((await r({ p_desen: "" })).error, null, "varsayılana dönüş serbest");
  await sql`insert into ortak.oduller (oyun_id, kullanici_id, odul, kaynak) values ('deneme', ${a.id}, 'desen-kazanilan', 'test')`;
  assert.equal((await r({ p_desen: "desen-kazanilan" })).data?.desen, "desen-kazanilan");
  // Halka'nın bağlama ödülü: sunucu vermeden istemci yazamaz (sessizce atlanır), verince yazılır
  const halka = (o: unknown) => a.c.schema("ortak").rpc("odul_kaydet", { p_oyun: "halka", p_oduller: o });
  const bag = (await sql`select ayarlar -> 'hesap' ->> 'baglama_odulu' as b from ortak.oyunlar where id = 'halka'`)[0]!.b as string;
  assert.ok(bag, "halka bağlama ödülü tanımlı");
  assert.equal((await halka([{ odul: bag }, { odul: "desen-sezon-test" }])).data, 1, "yalnız sezon ödülü yazıldı");
  await a.c.schema("ortak").rpc("baglama_odulu_al", { p_oyun: "halka" });
  assert.equal((await halka([{ odul: bag }])).data, 1, "sunucu verdikten sonra yazılır");
});
