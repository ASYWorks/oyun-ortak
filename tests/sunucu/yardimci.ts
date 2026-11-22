/**
 * Sunucu testleri yerel Supabase yığınına (oyun-test) karşı koşar: `npm run db:start`, sonra `npm run test:sunucu`.
 * Anahtarlar Supabase CLI'ın herkesçe bilinen yerel demo anahtarlarıdır; yalnız 127.0.0.1 kabul edilir.
 */
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import postgres from "postgres";

export const URL = process.env.SUPABASE_URL ?? "http://127.0.0.1:55321";
if (!/^http:\/\/(127\.0\.0\.1|localhost):/.test(URL)) throw new Error("Sunucu testleri yalnız yerel yığında koşar");
const ANON =
  process.env.SUPABASE_ANON_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";
const SERVIS =
  process.env.SUPABASE_SERVICE_ROLE_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";
export const DB_URL = process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:55322/postgres";
export const MAILPIT = process.env.MAILPIT_URL ?? "http://127.0.0.1:55324";

const ayar = { auth: { persistSession: false, autoRefreshToken: false } };
export const istemci = (): SupabaseClient => createClient(URL, ANON, ayar);
export const yonetici = (): SupabaseClient => createClient(URL, SERVIS, ayar);
export const sql = postgres(DB_URL, { max: 5, onnotice: () => {} });

export const rastgeleEposta = () => `t${crypto.randomUUID().slice(0, 12)}@test.local`;

/** Parolalı kalıcı kullanıcı (gerçek Google/Apple jetonu yerelde üretilemez; devir yolu aynıdır). */
export async function kaliciKullanici() {
  const eposta = rastgeleEposta();
  const parola = `P-${crypto.randomUUID()}`;
  const { data, error } = await yonetici().auth.admin.createUser({ email: eposta, password: parola, email_confirm: true });
  if (error) throw error;
  return { id: data.user.id, eposta, parola };
}

/** Hesabı yeni bir kalıcı kullanıcıyla açar (takma ad, bulut kaydı ve ödül kalıcı hesap ister); kullanıcı kimliğini döner. */
export async function kaliciGir(h: { supabase: SupabaseClient; disGiris: (gir: () => Promise<{ error: unknown }>) => Promise<unknown> }) {
  const k = await kaliciKullanici();
  await h.disGiris(() => h.supabase.auth.signInWithPassword({ email: k.eposta, password: k.parola }));
  return k.id;
}

export const ortak = (c: SupabaseClient) => c.schema("ortak");

export async function rpc<T = unknown>(c: SupabaseClient, ad: string, arg?: Record<string, unknown>): Promise<T> {
  const { data, error } = await ortak(c).rpc(ad, arg);
  if (error) throw new Error(error.message);
  return data as T;
}

/** Edge Function'ı doğrudan çağırır (durum kodunu görmek için). */
export async function fonksiyon(c: SupabaseClient | null, ad: string, govde: unknown) {
  const jeton = c ? (await c.auth.getSession()).data.session?.access_token : undefined;
  const r = await fetch(`${URL}/functions/v1/${ad}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: ANON, ...(jeton ? { Authorization: `Bearer ${jeton}` } : {}) },
    body: typeof govde === "string" ? govde : JSON.stringify(govde),
  });
  let veri: unknown = null;
  try {
    veri = await r.json();
  } catch {
    veri = null;
  }
  return { durum: r.status, veri: veri as Record<string, any> };
}

/** Testler arasında oyunun skor/lig tablolarını temizler (kullanıcılar kalır; her test kendi kullanıcısını açar). */
export async function oyunuTemizle(oyun = "deneme") {
  await sql`delete from ortak.lig_gruplari where oyun_id = ${oyun}`;
  await sql`delete from ortak.skorlar where oyun_id = ${oyun}`;
  await sql`delete from ortak.denemeler where oyun_id = ${oyun}`;
  await sql`delete from ortak.hiz_sinirlari`;
}

export const bugun = () => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date());

/** Testlerde oturumu kapatmadan "bu oyundaki hesabı sil" (hesap.hesabiSil ayrıca oturumu kapatır). */
export async function oyunSil(c: { schema: (s: string) => { rpc: (f: string, a: object) => PromiseLike<{ error: { message: string } | null }> } }, oyun: string) {
  const { error } = await c.schema("ortak").rpc("oyun_verisini_sil", { p_oyun: oyun });
  if (error) throw new Error(error.message);
}

/** Sıralamaya girebilmesi için kullanıcıya seçilmiş ad verir (15 Kasım 2026: ad seçmeden sıralama yok). */
export async function adVer(id: string, oyun = "deneme") {
  const ad = `T${crypto.randomUUID().replace(/-/g, "").slice(0, 12)}`;
  await sql`insert into ortak.oyuncular (oyun_id, kullanici_id, ad, ad_anahtari, ad_otomatik)
    values (${oyun}, ${id}, ${ad}, ortak.ad_anahtari(${ad}), false)
    on conflict (oyun_id, kullanici_id) do update set ad = excluded.ad, ad_anahtari = excluded.ad_anahtari, ad_otomatik = false`;
}

/**
 * Oyun günlük tablosunun verilen günlerini saklar; dönen işlev testten sonra aynen geri koyar. Testler dün/yarın satırlarını
 * silip yeniden yazıyor; geri konmazsa yerel yığında oyun oturumlarının yüklediği içerik kaybolur (İfade bulgusu, 22 Kasım).
 */
export async function gunlukKoru(sema: string, gunler: string[]): Promise<() => Promise<void>> {
  if (!/^[a-z]+$/.test(sema)) throw new Error("şema adı");
  const satirlar = await sql.unsafe(`select coalesce(jsonb_agg(to_jsonb(g)), '[]'::jsonb) as j from ${sema}.gunluk g where gun = any($1::date[])`, [gunler]);
  const json = satirlar[0]!.j;
  return async () => {
    await sql.begin(async (t) => {
      await t.unsafe(`set local ${sema}.duzeltme = 'evet'`);
      await t.unsafe(`delete from ${sema}.gunluk where gun = any($1::date[])`, [gunler]);
      await t.unsafe(`insert into ${sema}.gunluk select * from jsonb_populate_recordset(null::${sema}.gunluk, $1::jsonb)`, [json]);
    });
  };
}
