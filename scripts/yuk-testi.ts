// OL-6 yük testi: "gece yarısı N oyuncu" senaryosu (Halka). Yalnız test projesine karşı koşulur; canlı kurucu onayı ister.
//
// Hazırlık (bir kez):
//   node scripts/yuk-testi.ts hazirla   → N kalıcı test hesabı (yuk-<i>@yuk-testi.example) oluşturur (servis rolü)
// Koşu:
//   node scripts/yuk-testi.ts kos       → hesaplarla oturum açar, sonra her oyuncu ACILIS_SN içinde rastgele bir anda:
//       kayit_oku → halka_gunluk_dizin + halka_gunluk_dosya(GUN) → dogrula-halka basla → oyun boyunca her hamlede
//       halka_gunluk_kontrol (ortalama HAMLE_SN, en az 1,5 sn), son NABIZ_SN'de kontrol yoksa ortak.nabiz, bir anlam ipucu →
//       SURE_MIN..SURE_MAX sn sonra dogrula-halka gönderimi → ortak.siralama (ilk 100, çevre 10), lig_durumu,
//       PROFIL_ORAN kadarında profil → kayit_yaz. Her oyuncu kendi hesabı ve JWT'siyle (RLS yolu; servis rolü yalnız hazırlık).
//   Hata sınıfları ayrı (429, 5xx, 4xx, 30 sn zaman aşımı, ağ). Son 500 isteğin %20'si hataysa güvenli durdurma.
// Temizlik:
//   node scripts/yuk-testi.ts temizle   → test hesaplarını siler (skor, deneme, lig cascade ile gider)
//
// Ortam: SB_URL, SB_ANON, SB_SERVICE (test projesi), HALKA_DIZIN (halka-kelime yolu), N (1000), GUN (bugün, İstanbul),
//   ACILIS_SN (300), SURE_MIN (60), SURE_MAX (300), HAMLE_SN (6), NABIZ_SN (20), PROFIL_ORAN (0.3),
//   KONTROL (db | kenar | yok; KENAR_URL verilirse kenar). SB_SERVICE varsa koşuda sunucu ölçümleri (işlemci, bağlantı) de alınır.
// Oturum açma IP başına sınırlı (sign_in_sign_ups): koşudan önce testte sınır geçici yükseltilir (kurucu onayıyla).
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { monitorEventLoopDelay } from "node:perf_hooks";

const env = (k: string, v?: string): string => {
  const x = process.env[k] ?? v;
  if (x == null) throw new Error(`${k} yok`);
  return x;
};
const URL_ = env("SB_URL").replace(/\/$/, "");
const ANON = env("SB_ANON");
const N = Number(env("N", "1000"));
const PAROLA = "yuk-testi-" + ANON.slice(-12); // test hesapları için; gizli değil, hesaplar test projesinde ve koşu sonu silinir
const eposta = (i: number) => `yuk-${i}@yuk-testi.example`;
const bekle = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Aynı anda en çok `k` iş. */
async function havuz<T>(isler: (() => Promise<T>)[], k: number): Promise<T[]> {
  const sonuc: T[] = [];
  let i = 0;
  await Promise.all(Array.from({ length: k }, async () => {
    while (i < isler.length) { const j = i++; sonuc[j] = await isler[j]!(); }
  }));
  return sonuc;
}

async function hazirla() {
  const SERVIS = env("SB_SERVICE");
  let yeni = 0;
  await havuz(Array.from({ length: N }, (_, i) => async () => {
    const r = await fetch(`${URL_}/auth/v1/admin/users`, {
      method: "POST", headers: { apikey: SERVIS, Authorization: `Bearer ${SERVIS}`, "Content-Type": "application/json" },
      body: JSON.stringify({ email: eposta(i), password: PAROLA, email_confirm: true }),
    });
    if (r.ok) yeni++;
    else if (r.status !== 422) console.error(i, r.status, await r.text());
  }), 10);
  console.log(`hazır: ${N} hesap (${yeni} yeni)`);
}

async function temizle() {
  const SERVIS = env("SB_SERVICE");
  const h = { apikey: SERVIS, Authorization: `Bearer ${SERVIS}` };
  let silinen = 0;
  for (let sayfa = 1; ; sayfa++) {
    const r = await fetch(`${URL_}/auth/v1/admin/users?page=${sayfa}&per_page=1000`, { headers: h });
    const { users } = (await r.json()) as { users: { id: string; email?: string }[] };
    const bizim = users.filter((u) => u.email?.endsWith("@yuk-testi.example"));
    await havuz(bizim.map((u) => async () => { if ((await fetch(`${URL_}/auth/v1/admin/users/${u.id}`, { method: "DELETE", headers: h })).ok) silinen++; }), 10);
    if (users.length < 1000) break;
    if (bizim.length) sayfa--; // silinenler sayfalamayı kaydırır
  }
  console.log(`silindi: ${silinen}`);
}

// ---------------------------------------------------------------- ölçüm
const sureler: Record<string, number[]> = {};
const sinif = { "429": 0, "5xx": 0, "4xx": 0, zaman_asimi: 0, ag: 0 };
/** Güvenli durdurma: son 500 isteğin %20'den fazlası hataysa yeni iş başlatılmaz (test projesini çökertmemek için). */
const son: number[] = [];
let durduruldu = false;
const kotu = () => {
  if (son.length > 500) son.splice(0, son.length - 500);
  if (!durduruldu && son.length >= 200 && son.reduce((a, b) => a + b, 0) / son.length > 0.2) {
    durduruldu = true;
    console.log("GÜVENLİ DURDURMA: son isteklerin %20'sinden fazlası hata");
  }
  return durduruldu;
};
const hatalar: Record<string, number> = {};
async function cagri(tur: string, yol: string, jeton: string, govde: unknown, ek: Record<string, string> = {}): Promise<unknown> {
  const t0 = performance.now();
  let durum = 0;
  try {
    const r = await fetch(yol.startsWith("https://") ? yol : `${URL_}${yol}`, {
      method: "POST", headers: { apikey: ANON, Authorization: `Bearer ${jeton}`, "Content-Type": "application/json", ...ek },
      body: JSON.stringify(govde), signal: AbortSignal.timeout(30_000),
    });
    durum = r.status;
    const v = await r.json().catch(() => null);
    son.push(r.ok ? 0 : 1);
    if (!r.ok) {
      sinif[r.status === 429 ? "429" : r.status >= 500 ? "5xx" : "4xx"]++;
      const k = `${tur} ${durum} ${(v as { error?: string; message?: string } | null)?.error ?? (v as { message?: string } | null)?.message ?? ""}`.trim().slice(0, 90);
      hatalar[k] = (hatalar[k] ?? 0) + 1;
    }
    return r.ok ? v : null;
  } catch (e) {
    const neden = (e as Error).name === "TimeoutError" ? "zaman_asimi" : "ag";
    son.push(1);
    sinif[neden]++;
    hatalar[`${tur} ${neden}`] = (hatalar[`${tur} ${neden}`] ?? 0) + 1;
    return null;
  } finally {
    (sureler[tur] ??= []).push(performance.now() - t0);
  }
}
const rpc = (ad: string, jeton: string, args: unknown, sema?: string) =>
  cagri(`rpc ${ad}`, `/rest/v1/rpc/${ad}`, jeton, args, sema ? { "Content-Profile": sema } : {});
const fn = (tur: string, jeton: string, govde: unknown) => cagri(`edge ${tur}`, "/functions/v1/dogrula-halka", jeton, govde);

const yuzdelik = (a: number[], p: number) => a.length ? [...a].sort((x, y) => x - y)[Math.min(a.length - 1, Math.floor(a.length * p))]! : NaN;

async function kos() {
  const HALKA = env("HALKA_DIZIN");
  const GUN = env("GUN", new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date()));
  const ACILIS = Number(env("ACILIS_SN", "300")) * 1000;
  const SMIN = Number(env("SURE_MIN", "60")), SMAX = Number(env("SURE_MAX", "300"));
  const HAMLE = Number(env("HAMLE_SN", "6")), NABIZ = Number(env("NABIZ_SN", "20")), PROFIL_ORAN = Number(env("PROFIL_ORAN", "0.3"));
  const KENAR_URL = process.env.KENAR_URL ?? "";
  const KONTROL = env("KONTROL", KENAR_URL ? "kenar" : "db");
  if (!["db", "kenar", "yok"].includes(KONTROL) || (KONTROL === "kenar" && !KENAR_URL)) throw new Error("KONTROL: db | kenar (KENAR_URL ile) | yok");
  const tamGun = (JSON.parse(readFileSync(join(HALKA, "data/build/gunluk_tam.json"), "utf8")) as Record<string, unknown>)[GUN];
  if (!tamGun) throw new Error(`${GUN} gunluk_tam.json'da yok`);
  const bas = (tamGun as { puzzle: { start: { rot: number[]; flip: boolean[] } } }).puzzle.start;
  const { gecerliGonderim } = (await import(pathToFileURL(join(HALKA, "scripts/yuk_gonderim.ts")).href)) as {
    gecerliGonderim: (g: unknown, s: number) => Record<string, unknown>;
  };

  // Oturumlar (koşudan önce; ölçüme girmez).
  // Captcha açıkken (19 Kasım'dan beri testte de) parolalı giriş jeton ister: oturum yönetici bağlantısıyla açılır
  // (tek kullanımlık kod; /verify captcha istemez). Servis anahtarı yalnız bu hazırlıkta kullanılır.
  const SERVIS = env("SB_SERVICE");
  const jetonlar = (await havuz(Array.from({ length: N }, (_, i) => async () => {
    const l = await fetch(`${URL_}/auth/v1/admin/generate_link`, {
      method: "POST", headers: { apikey: SERVIS, Authorization: `Bearer ${SERVIS}`, "Content-Type": "application/json" },
      body: JSON.stringify({ type: "magiclink", email: eposta(i) }),
    });
    const lj = (await l.json()) as { hashed_token?: string; properties?: { hashed_token?: string } };
    const r = await fetch(`${URL_}/auth/v1/verify`, {
      method: "POST", headers: { apikey: ANON, "Content-Type": "application/json" },
      body: JSON.stringify({ type: "magiclink", token_hash: lj.hashed_token ?? lj.properties?.hashed_token }),
    });
    return r.ok ? ((await r.json()) as { access_token: string }).access_token : (console.error(i, r.status, await r.text()), null);
  }), 10)).filter((x): x is string => !!x);
  console.log(`oturum: ${jetonlar.length}/${N}`);
  if (jetonlar.length < N) throw new Error("oturum açılamayan hesap var (sınır?)");

  // Sunucu ölçümleri (Prometheus uç noktası, servis rolü), 15 sn'de bir: işlemci (diske bekleme ayrı), takas, bağlantı, PostgREST
  // havuz bekleyeni. 19 Kasım: Nano'da darboğaz bellek; işlemci yüzdesinin çoğu diske bekleme (takas) çıktı.
  const ornek: { cpu: number; iowait: number; takas: number; baglanti: number; bekleyen: number }[] = [];
  let durdur = () => {};
  if (process.env.SB_SERVICE) {
    const yetki = "Basic " + Buffer.from(`service_role:${process.env.SB_SERVICE}`).toString("base64");
    const oku = async () => {
      const m = await (await fetch(`${URL_}/customer/v1/privileged/metrics`, { headers: { Authorization: yetki } })).text();
      let bos = 0, toplam = 0, iow = 0, takas = 0, baglanti = 0, bekleyen = 0;
      for (const l of m.split("\n")) {
        const v = Number(l.slice(l.lastIndexOf(" ") + 1));
        if (l.startsWith("node_cpu_seconds_total{") && l.includes('service_type="db"')) { toplam += v; if (l.includes('mode="idle"')) bos += v; if (l.includes('mode="iowait"')) iow += v; }
        else if (l.startsWith("node_vmstat_pswpin{")) takas = v;
        else if (l.startsWith("pg_stat_database_num_backends{")) baglanti = v;
        else if (l.startsWith("pgrst_db_pool_waiting{")) bekleyen = v;
      }
      return { bos, toplam, iow, takas, t: Date.now(), baglanti, bekleyen };
    };
    let onceki = await oku().catch(() => null);
    const z = setInterval(async () => {
      const x = await oku().catch(() => null);
      if (x && onceki && x.toplam > onceki.toplam) ornek.push({
        cpu: 1 - (x.bos - onceki.bos) / (x.toplam - onceki.toplam), iowait: (x.iow - onceki.iow) / (x.toplam - onceki.toplam),
        takas: ((x.takas - onceki.takas) * 1000) / (x.t - onceki.t), baglanti: x.baglanti, bekleyen: x.bekleyen,
      });
      onceki = x ?? onceki;
    }, 15_000);
    durdur = () => clearInterval(z);
  }

  const gecikme = monitorEventLoopDelay({ resolution: 20 });
  gecikme.enable();
  const cpu0 = process.cpuUsage();
  const t0 = Date.now();
  let biten = 0;
  await Promise.all(jetonlar.map(async (j) => {
    await bekle(Math.random() * ACILIS);
    const kayit = (await rpc("kayit_oku", j, { p_oyun: "halka" }, "ortak")) as { surum?: number } | null;
    await rpc("halka_gunluk_dizin", j, {});
    await rpc("halka_gunluk_dosya", j, { p_tarih: GUN });
    const basla = (await fn("basla", j, { islem: "basla", gun: GUN })) as { bilet?: string } | null;
    const sure = SMIN + Math.random() * (SMAX - SMIN);
    const bitis = Date.now() + sure * 1000;
    // Oyun: her hamlede kontrol (en az 1,5 sn arayla; Halka 19 Kasım), hamle arası üstel dağılım (ortalama HAMLE_SN).
    // KONTROL=db: kontrol RPC'si, nabız da sayar (göç 5700); son NABIZ_SN'de kontrol gitmediyse nabız.
    // KONTROL=kenar: kontrol KENAR_URL'ye (bilet ile), KONTROL=yok: kontrol sunucuya gitmez (kenar sonrası DB yükü);
    // bu ikisinde kontrol nabız saymaz, nabız her NABIZ_SN'de gider. İlk hamlede bir anlam ipucu.
    let sonIstek = Date.now(), ipucu = false;
    while (Date.now() < bitis - 1500 && !kotu()) {
      const hamle = Date.now() + Math.max(1500, -Math.log(1 - Math.random()) * HAMLE * 1000);
      const nabizAni = sonIstek + NABIZ * 1000;
      const an = Math.min(hamle, nabizAni);
      await bekle(Math.max(0, Math.min(an, bitis) - Date.now()));
      if (Date.now() >= bitis) break;
      if (an === nabizAni) {
        await rpc("nabiz", j, { p_oyun: "halka", p_anahtar: `gunluk:${GUN}`, p_durdur: false }, "ortak");
        sonIstek = Date.now();
      } else if (KONTROL === "db") {
        await rpc("halka_gunluk_kontrol", j, { p_tarih: GUN, p_rot: bas.rot, p_flip: bas.flip });
        sonIstek = Date.now();
      } else if (KONTROL === "kenar") {
        await cagri("kenar kontrol", KENAR_URL, j, { bilet: basla?.bilet, rot: bas.rot, flip: bas.flip });
      }
      if (!ipucu) {
        ipucu = true;
        await rpc("halka_gunluk_ipucu", j, { p_tarih: GUN, p_tur: "anlam", p_sira: 0, p_rot: bas.rot, p_flip: bas.flip });
      }
    }
    if (kotu()) return;
    await bekle(Math.max(0, bitis - Date.now()) + 1000);
    await fn("gonder", j, { ...gecerliGonderim(tamGun, Math.floor(sure)), cihaz: randomUUID() });
    const tablo = (await rpc("siralama", j, { p_oyun: "halka", p_tur: "gunluk", p_donem: GUN, p_ilk: 100, p_cevre: 10 }, "ortak")) as
      { satirlar?: { profil?: string }[] } | null;
    await rpc("lig_durumu", j, { p_oyun: "halka" }, "ortak");
    // Oyuncuların bir kısmı tablodan bir profile bakar (girişli: sınır kimliğe bağlı).
    const pr = tablo?.satirlar?.[Math.floor(Math.random() * tablo.satirlar.length)]?.profil;
    if (pr && Math.random() < PROFIL_ORAN) await rpc("profil", j, { p_oyun: "halka", p_profil: pr }, "ortak");
    await rpc("kayit_yaz", j, { p_oyun: "halka", p_veri: { yuk: GUN }, p_surum: kayit?.surum ?? 0 }, "ortak");
    if (++biten % 100 === 0) console.log(`${biten}/${N} bitti (${Math.round((Date.now() - t0) / 1000)} sn)`);
  }));
  durdur();

  gecikme.disable();
  const gecen = (Date.now() - t0) / 1000;
  const c = process.cpuUsage(cpu0);
  console.log(`\nN=${N}, süre ${Math.round(gecen)} sn, gün ${GUN}, hamle ort ${HAMLE} sn, nabız ${NABIZ} sn, kontrol ${KONTROL}${durduruldu ? ", GÜVENLİ DURDURULDU" : ""}`);
  // Yük üretici darboğaz mı: işlemci (bir çekirdeğin yüzdesi) ve olay döngüsü gecikmesi yüksekse ölçüm güvenilmez.
  console.log(`yük üretici: işlemci %${((100 * (c.user + c.system)) / 1e6 / gecen).toFixed(0)}, olay döngüsü gecikmesi p99 ${(gecikme.percentile(99) / 1e6).toFixed(0)} ms`);
  console.log("tür".padEnd(26), "adet".padStart(6), "istek/sn".padStart(8), "p50".padStart(7), "p95".padStart(7), "p99".padStart(7), "en çok".padStart(8));
  for (const [t, a] of Object.entries(sureler))
    console.log(t.padEnd(26), String(a.length).padStart(6), (a.length / gecen).toFixed(1).padStart(8), ...[0.5, 0.95, 0.99].map((p) => yuzdelik(a, p).toFixed(0).padStart(7)), Math.max(...a).toFixed(0).padStart(8));
  const toplam = Object.values(sureler).reduce((s, a) => s + a.length, 0);
  const hataSay = Object.values(hatalar).reduce((s, n) => s + n, 0);
  console.log(`\ntoplam ${(toplam / gecen).toFixed(0)} istek/sn; hata: ${hataSay}/${toplam} (%${((100 * hataSay) / toplam).toFixed(2)})`, sinif, hatalar);
  if (ornek.length) {
    const c = ornek.map((o) => o.cpu * 100);
    console.log(`DB işlemci %: ortanca ${yuzdelik(c, 0.5).toFixed(0)}, p95 ${yuzdelik(c, 0.95).toFixed(0)}, en çok ${Math.max(...c).toFixed(0)}`);
    const w = ornek.map((o) => o.iowait * 100);
    console.log(`  bunun diske bekleme payı en çok %${Math.max(...w).toFixed(0)}; takastan okuma en çok ${Math.max(...ornek.map((o) => o.takas)).toFixed(0)} sayfa/sn`);
    console.log(`DB bağlantı en çok ${Math.max(...ornek.map((o) => o.baglanti))}; PostgREST havuz bekleyeni en çok ${Math.max(...ornek.map((o) => o.bekleyen))}`);
  }
}

const islem = process.argv[2];
await (islem === "hazirla" ? hazirla() : islem === "kos" ? kos() : islem === "temizle" ? temizle() : Promise.reject(new Error("hazirla | kos | temizle")));
