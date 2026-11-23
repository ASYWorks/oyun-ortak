/**
 * hesap: misafir (anonim oturum) → Google / Apple / e-posta kodu; takma ad; bulut kaydı; silme.
 *
 * Misafir: oyuncu hiç giriş yapmadan oynar. Sunucuya ilk iş gerektiğinde (skor gönderimi vb.) anonim oturum açılır.
 * Kalıcı hesaba geçiş her yöntemde aynı yoldan yürür: anonim oturum kısa ömürlü bir devir kodu alır,
 * oyuncu girer, `hesap_devral` anonim hesabın sunucu satırlarını yeni ya da var olan hesaba taşır.
 * Yerel kayıt, oyunun birleştirme işleviyle bulut kaydına katılır (KM-3, EN-5, HK-4).
 */
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Depo } from "../kayit/index.ts";
import type { LigDurumu } from "../siralama/index.ts";
export * from "./dugmeler.ts";

export type Saglayici = "google" | "apple";

export interface Ben {
  ad: string | null;
  ad_otomatik: boolean;
  ad_degisti: string | null;
  kademe: number;
  seviye_puani: number;
  baglama_odulu: string | null;
  yas_onay: string | null;
  anonim: boolean;
}

/**
 * Açılış yanıtı. `surum` damgaları opak (eşitlik karşılaştırması için): profil (kendi profilin; lig ve turnuva sırası hariç,
 * gün değişince de değişir), oduller (`odullerim`), haklar (`haklarim`), kayit (bulut kaydının sürüm numarası).
 */
export interface Acilis {
  ben: Ben;
  surum: { profil: string; oduller: string; haklar: string; kayit: number };
  /** Oyunda lig varsa lig durumu (siralama.lig() ile aynı; sık değiştiği için damga yerine kendisi). */
  lig?: LigDurumu;
  /**
   * Sunucu kontrollü bayraklar (ortak.oyunlar.ayarlar.bayraklar; göç 6800). Oyun kendi anlamını verir. Öneri:
   * `kapali`: geçici olarak kapatılan özellikler (ör. "turnuva"), `asgari_surum`: bunun altındaki istemci güncelleme ister,
   * `duyuru`: oyuncuya gösterilecek kısa metin. Boşsa {}.
   */
  bayraklar: {
    kapali?: string[]; asgari_surum?: string; duyuru?: string;
    /** Yayın öncesi önizleme (göç 8280): true iken oyun yalnız vitrin seviyelerini açar; testçi değilse günlük, lig,
     *  etkinlik, sıralama ve düello zaten `kapali` içindedir (sekme ve metin gösterilmez). */
    onizleme?: boolean;
    /** Önizlemede test listesindeki hesap: her şey açık, bütün seviyeler açılır. */
    testci?: boolean;
    /** Yayın tarihi 'YYYY-AA-GG' (göç 8290); yoksa belli değil. "Gün N", arşivin başı ve etkinlik takvimi buna göre. */
    yayin_tarihi?: string;
    [k: string]: unknown;
  };
}

export type AdSonucu =
  | { durum: "ok"; ad: string }
  | { durum: "bicim" | "uygunsuz" | "alinmis" }
  | { durum: "bekle"; bekle_gun: number };

export interface GirisSonucu {
  /** Anonim hesaptan taşınan verinin olduğu oyunlar. */
  devredilen: string[];
  /**
   * Skorlar, denemeler ve lig yalnız yeni açılan hesaba taşınır. Var olan hesaba girildiyse false:
   * misafirken gönderilen skorlar sayılmaz; ad ve bulut kaydı yine taşınır.
   */
  skorlarTasindi?: boolean;
  /** Devir kodu süresi dolmuş ya da geçersizse true; anonim hesabın sunucu verisi taşınamadı. */
  devirBasarisiz?: boolean;
}

export interface Birlesim<T> {
  kayit: T;
  /** Oyuncuya gösterilecek kısa özet (ör. "12 seviye ve 5 gün eklendi"). */
  ozet?: string;
}

export interface HesapAyari {
  supabase: SupabaseClient;
  oyunId: string;
  /** Web yönlendirmeli girişte devir kodunu sayfa yenilemesine taşımak için. */
  depo: Depo;
  /**
   * Bot koruması (OL-9, Cloudflare Turnstile): her çağrıda yeni bir doğrulama jetonu döner. Verilirse e-posta kodu,
   * anonim giriş ve kimlik jetonuyla giriş isteğine eklenir. Projede captcha açıksa zorunludur.
   */
  captcha?: () => Promise<string>;
}

const DEVIR = "oyun-ortak:devir";

/** jsonb gibi karşılaştırır: anahtar sırası ve undefined alanlar sayılmaz. */
const sirali = (v: unknown): unknown =>
  Array.isArray(v) ? v.map(sirali)
  : v && typeof v === "object" ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sirali((v as Record<string, unknown>)[k])]))
  : v;
export const ayniJson = (x: unknown, y: unknown) =>
  JSON.stringify(sirali(JSON.parse(JSON.stringify(x ?? null)))) === JSON.stringify(sirali(JSON.parse(JSON.stringify(y ?? null))));

export function hesapBaslat(a: HesapAyari) {
  const sb = a.supabase;
  const ortak = () => sb.schema("ortak");

  async function rpc<T>(ad: string, arg?: Record<string, unknown>): Promise<T> {
    const { data, error } = await ortak().rpc(ad, arg);
    if (error) throw new Error(error.message);
    return data as T;
  }

  const oturum = async () => (await sb.auth.getSession()).data.session;
  const oturumKimligi = async (): Promise<string | null> => (await oturum())?.user.id ?? null;
  /** Bulut kaydının bu oturumda son bilinen hâli (hesaba bağlı; başka hesapta kullanılmaz). */
  let bulutBilinen: { kim: string | null; veri: unknown; surum: number } | null = null;
  const jeton = async () => (a.captcha ? { captchaToken: await a.captcha() } : {});

  /** Kalıcı girişin ortak gövdesi: anonimse devir kodu al, gir, devral. */
  async function kaliciGiris(gir: () => Promise<{ error: unknown }>, kodHazir?: string | null): Promise<GirisSonucu> {
    const s = await oturum();
    const kod = kodHazir ?? (s?.user.is_anonymous ? await rpc<string>("devir_kodu_al") : null);
    const { error } = await gir();
    if (error) throw error instanceof Error ? error : new Error(String((error as { message?: string }).message ?? error));
    if (!kod) return { devredilen: [] };
    try {
      const r = await rpc<{ oyunlar: string[]; skorlar_tasindi: boolean }>("hesap_devral", { p_kod: kod });
      return { devredilen: r.oyunlar, skorlarTasindi: r.skorlar_tasindi };
    } catch {
      return { devredilen: [], devirBasarisiz: true };
    }
  }

  return {
    supabase: sb,

    async kullanici() {
      const s = await oturum();
      return s ? { id: s.user.id, anonim: s.user.is_anonymous === true, eposta: s.user.email ?? null } : null;
    },

    /** Oturum yoksa anonim oturum açar. Sunucuya ilk iş gerektiğinde çağrılır. */
    async anonimGir(): Promise<string> {
      const s = await oturum();
      if (s) return s.user.id;
      const { data, error } = await sb.auth.signInAnonymously({ options: await jeton() });
      if (error || !data.user) throw error ?? new Error("anonim_giris");
      return data.user.id;
    },

    /** Yerel Google/Apple eklentisinden gelen kimlik jetonuyla giriş (Android/iOS). */
    idTokenIleGir(saglayici: Saglayici, token: string, nonce?: string) {
      // Captcha jetonu istenmez: Supabase kimlik jetonuyla girişte captcha denetlemiyor (19 Kasım test projesinde
      // sınandı: jetonsuz istek doğrudan kimlik jetonu doğrulamasına gidiyor). Jeton beklemek ilk girişi düşürüyordu
      // (Turnstile hazır değilken), güvenliği Google/Apple'ın imzalı jetonu sağlar.
      return kaliciGiris(async () => sb.auth.signInWithIdToken({ provider: saglayici, token, nonce }));
    },

    /** Web'de yönlendirmeli giriş. Dönüşte `webDonusunuTamamla` çağrılır. */
    async webIleGir(saglayici: Saglayici, donusAdresi: string): Promise<void> {
      const s = await oturum();
      if (s?.user.is_anonymous) await a.depo.yaz(DEVIR, await rpc<string>("devir_kodu_al"));
      const { error } = await sb.auth.signInWithOAuth({ provider: saglayici, options: { redirectTo: donusAdresi } });
      if (error) throw error;
    },

    /** Yönlendirmeden dönünce (oturum supabase-js tarafından kurulduktan sonra) devri tamamlar. */
    async webDonusunuTamamla(): Promise<GirisSonucu | null> {
      const kod = await a.depo.oku(DEVIR).catch(() => null);
      const s = await oturum();
      if (!kod || !s || s.user.is_anonymous) return null;
      await a.depo.sil(DEVIR).catch(() => {});
      return kaliciGiris(async () => ({ error: null }), kod);
    },

    /**
     * E-posta kodu (yedek yöntem). `dil` e-postanın dilini ve göndereni seçer: "tr" giris@asyworks.com, "en"
     * login@asyworks.com (bulutta giris-epostasi kancası). Verilmezse Türkçe. Yönlendirme adresi yalnız dili taşır;
     * kodla girişte bağlantı kullanılmaz.
     */
    async epostaKoduGonder(eposta: string, dil?: "tr" | "en"): Promise<void> {
      const options = dil
        ? { shouldCreateUser: true, emailRedirectTo: `https://asyworks.com/?dil=${dil}`, data: { dil }, ...(await jeton()) }
        : { shouldCreateUser: true, ...(await jeton()) };
      const { error } = await sb.auth.signInWithOtp({ email: eposta, options });
      if (error) throw error;
    },
    epostaKoduIleGir(eposta: string, kod: string) {
      return kaliciGiris(() => sb.auth.verifyOtp({ email: eposta, token: kod, type: "email" }));
    },

    /** Başka bir giriş yöntemi (ör. testlerde parola) için genel kapı; devir aynı biçimde işler. */
    disGiris: (gir: () => Promise<{ error: unknown }>) => kaliciGiris(gir),

    async cikis() {
      await sb.auth.signOut();
    },

    ben: () => rpc<Ben>("ben", { p_oyun: a.oyunId }),
    /**
     * Oturum gerekmeden oyunun halka açık bayrakları (göç 8310): testçi olmayan birinin göreceği `kapali`, `onizleme`,
     * `yayin_tarihi`, `duyuru`, `asgari_surum`. Oturumu olmayan misafir önizleme kilidini buradan uygular; oturum varsa
     * `acilis().bayraklar` kullanılır (testçi bilgisi orada).
     */
    oyunBayraklari: () => rpc<Acilis["bayraklar"]>("oyun_bayraklari", { p_oyun: a.oyunId }),
    /**
     * Açılışta tek istek (göç 20261120006500): `ben` ile aynı işi yapar ve her bilgi için sürüm damgası döner. İstemci
     * cihazdaki kopyanın damgası aynıysa o bilgiyi istemez. Önbellek hesap kimliğine göre ayrılmalı (çıkışta başkası görmesin).
     */
    async acilis() {
      const r = await rpc<Acilis>("acilis", { p_oyun: a.oyunId });
      // Başka cihaz bulut kaydını değiştirdiyse bellekteki kopya düşer; bulutKaydi().birlestir yeniden okur.
      if (bulutBilinen && bulutBilinen.surum !== r.surum.kayit) bulutBilinen = null;
      return r;
    },
    yasOnayla: () => rpc<void>("yas_onayla"),
    /** Yalnız kalıcı hesap (misafirde `kalici_hesap_gerekli`); misafir `otomatikAd` kullanır. */
    adDegistir: (ad: string) => rpc<AdSonucu>("ad_degistir", { p_oyun: a.oyunId, p_ad: ad }),

    /**
     * Otomatik ad: sunucu `#` + 5 karakter üretir (ör. "#K7P2X"). Misafire ad sorulmaz, bu ad verilir; kendi adını
     * yalnız giriş yapan oyuncu seçer (`adDegistir`). Yalnız adı olmayan oyuncuya verilir; adı varsa onu döner.
     */
    otomatikAd: () => rpc<AdSonucu>("otomatik_ad", { p_oyun: a.oyunId }),

    /** İlk kalıcı hesapta bir kez verilen kozmetik ödül kimliği; verildiyse null. */
    baglamaOdulu: () => rpc<string | null>("baglama_odulu_al", { p_oyun: a.oyunId }),

    /** Yalnız kalıcı hesap yazar (misafirde `kalici_hesap_gerekli`); misafirin kaydı yerelde kalır, girişten sonra birleşir. */
    bulutKaydi<T>() {
      const oku = async () => {
        const r = await rpc<{ veri: T; surum: number } | null>("kayit_oku", { p_oyun: a.oyunId });
        bulutBilinen = r ? { kim: await oturumKimligi(), veri: r.veri, surum: r.surum } : null;
        return r;
      };
      return {
        oku,
        /**
         * Yerel kaydı bulut kaydıyla oyunun işleviyle birleştirip yazar. Arada başka cihaz yazdıysa
         * yeniden okur ve yeniden birleştirir (iyimser kilit). Son okunan/yazılan kayıt bu hesap için bellekte
         * tutulur: ilk deneme okumadan yapılır, sürüm tutmazsa (başka cihaz yazdı) okunur. `acilis()` bulut damgası
         * bilinenle farklıysa belleği düşürür.
         */
        async birlestir(yerel: T, birlestir: (yerel: T, uzak: T) => Birlesim<T>, secenek: { kim?: string } = {}): Promise<Birlesim<T>> {
          const kim = await oturumKimligi();
          // MD-24: yerel kayıt hangi hesaba aitse o verilir; oturum arada başka hesaba geçtiyse başkasının kaydına karışmasın.
          if (secenek.kim !== undefined && secenek.kim !== kim) throw new Error("hesap_degisti");
          for (let i = 0; i < 4; i++) {
            const bilinen = i === 0 && bulutBilinen && bulutBilinen.kim === kim ? bulutBilinen : null;
            const uzak = bilinen ? { veri: bilinen.veri as T, surum: bilinen.surum } : await oku();
            const b = uzak ? birlestir(yerel, uzak.veri) : { kayit: yerel };
            if (uzak && ayniJson(b.kayit, uzak.veri)) return b; // değişmeyen kayıt yazılmaz (GC-2)
            const s = await rpc<number | null>("kayit_yaz", { p_oyun: a.oyunId, p_veri: b.kayit, p_surum: uzak?.surum ?? 0 });
            if (s != null) {
              bulutBilinen = { kim, veri: b.kayit, surum: s };
              return b;
            }
            bulutBilinen = null;
          }
          throw new Error("kayit_cakisma");
        },
      };
    },

    /**
     * Sıralamada görünen adla şikâyet (KH-5). Yalnız kalıcı hesaplar şikâyet edebilir. 'ad' şikâyeti eşiğe
     * ulaşınca hedefin adı sıfırlanır; 'hile' ve 'diger' inceleme için kaydedilir. Günde en çok 20.
     */
    sikayetEt: (ad: string, neden: "ad" | "hile" | "diger") =>
      rpc<{ durum: "ok" | "zaten" | "bulunamadi" | "kendin"; ad_sifirlandi?: boolean }>("sikayet_et", {
        p_oyun: a.oyunId, p_ad: ad, p_neden: neden,
      }),

    /**
     * "Hesabımı sil" (bu oyunda). Hesaplar oyuncunun gözünde oyun oyun ayrıdır: yalnız bu oyunun verisi silinir;
     * kişinin başka oyunda verisi yoksa sunucu giriş kaydını (e-posta, Google/Apple kimliği) da siler. Ardından bu
     * cihazda oturum kapanır. Başka oyunlar hiçbir yerde anılmaz.
     */
    async hesabiSil() {
      await rpc<void>("oyun_verisini_sil", { p_oyun: a.oyunId });
      await sb.auth.signOut({ scope: "local" });
    },
  };
}

export type Hesap = ReturnType<typeof hesapBaslat>;

// ---------------------------------------------------------------- web: Google'ın kendi düğmesi

/**
 * Tek kullanımlık nonce: `ozet` (SHA-256, hex) Google'a, `ham` Supabase'e verilir. Supabase jetondaki
 * özetin ham değerden üretildiğini denetler; çalınan jeton başka oturumda kullanılamaz.
 */
export async function googleNonce(): Promise<{ ham: string; ozet: string }> {
  const b = crypto.getRandomValues(new Uint8Array(32));
  const ham = Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
  const h = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(ham)));
  return { ham, ozet: Array.from(h, (x) => x.toString(16).padStart(2, "0")).join("") };
}

interface GoogleKimlik {
  initialize(o: Record<string, unknown>): void;
  renderButton(kap: HTMLElement, o: Record<string, unknown>): void;
}
let gsiYukleniyor: Promise<GoogleKimlik> | undefined;
function gsiYukle(): Promise<GoogleKimlik> {
  const hazir = () => (globalThis as { google?: { accounts?: { id?: GoogleKimlik } } }).google?.accounts?.id;
  return (gsiYukleniyor ??= new Promise((tamam, hata) => {
    if (hazir()) return tamam(hazir()!);
    const s = document.createElement("script");
    s.src = "https://accounts.google.com/gsi/client";
    s.async = true;
    s.onload = () => (hazir() ? tamam(hazir()!) : hata(new Error("google_yuklenemedi")));
    s.onerror = () => {
      gsiYukleniyor = undefined;
      hata(new Error("google_yuklenemedi"));
    };
    document.head.appendChild(s);
  }));
}

export interface GoogleDugmesiAyari {
  /** Google Cloud'daki Web istemcisinin Client ID'si (gizli değil). */
  clientId: string;
  /** Düğmenin çizileceği öğe. */
  kap: HTMLElement;
  sonuc: (r: GirisSonucu) => void;
  hata?: (e: unknown) => void;
  metin?: "continue_with" | "signin_with" | "signup_with";
  /** Düğme genişliği (px). Google en çok 400 kabul eder; fazlası 400'e indirilir. Verilmezse Google'ın kendi genişliği. */
  genislik?: number;
  /** Düğme metninin dili (ör. "tr", "en"). Verilmezse "tr". Oyunun o anki dili verilir. */
  dil?: string;
}

/**
 * Web'de "Google ile devam et": Google Identity Services düğmesi. Yönlendirmeli girişten farkı, oyuncunun
 * Supabase adresini değil oyunun kendi adresini görmesi. Jeton sayfaya gelir, `idTokenIleGir` ile Supabase'e
 * iletilir; misafir verisinin devri aynı yoldan işler. Sayfanın adresi Google istemcisinin
 * "Authorized JavaScript origins" listesinde olmalıdır.
 */
export async function googleDugmesi(hesap: Hesap, a: GoogleDugmesiAyari): Promise<void> {
  const gsi = await gsiYukle();
  const { ham, ozet } = await googleNonce();
  gsi.initialize({
    client_id: a.clientId,
    nonce: ozet,
    use_fedcm_for_prompt: true,
    callback: async (yanit: { credential?: string }) => {
      try {
        if (!yanit.credential) throw new Error("google_jeton_yok");
        a.sonuc(await hesap.idTokenIleGir("google", yanit.credential, ham));
      } catch (e) {
        a.hata?.(e);
      }
    },
  });
  gsi.renderButton(a.kap, {
    theme: "outline", size: "large", shape: "pill", text: a.metin ?? "continue_with", locale: a.dil ?? "tr",
    ...(a.genislik ? { width: Math.min(400, Math.max(200, Math.round(a.genislik))) } : {}),
  });
}
