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
/** Web devir kaydının ömrü (D03): sunucudaki kısa ömürlü devir kodundan uzun tutulmaz. */
const DEVIR_OMRU = 30 * 60_000;
/**
 * Web yönlendirmeli girişin yerel devir kaydı (D03). `sahip`: ilk uygun (kalıcı, jetonlu) OAuth dönüşündeki hesap; kayıt yalnız
 * o hesapta denenir. `id`: kaydı ayırır, eski işlem daha yeni bir kaydı silemez. Eski sürümde depoda ham kod metni durur.
 */
interface DevirKaydi { id: string; kod: string; olusturma: number; sahip: string | null }

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
  // `dogrulandi`: girdi hesap doğrulamalı çağrıdan geldi (MD-24); doğrulamalı birleştirme yalnız bunlara güvenir, çünkü eski yolda
  // `kim` yanıttan sonra okunur ve arada oturum değişirse yanlış hesaba bağlanabilir.
  let bulutBilinen: { kim: string | null; veri: unknown; surum: number; dogrulandi?: true } | null = null;
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

  // ---- web devir kaydı (D03) ----
  const devirOku = async (): Promise<DevirKaydi | null> => {
    const ham = await a.depo.oku(DEVIR).catch(() => null);
    if (!ham) return null;
    try {
      const v = JSON.parse(ham) as Partial<DevirKaydi>;
      if (v && typeof v === "object" && typeof v.kod === "string" && typeof v.id === "string" && typeof v.olusturma === "number")
        return { id: v.id, kod: v.kod, olusturma: v.olusturma, sahip: typeof v.sahip === "string" ? v.sahip : null };
    } catch { /* eski biçim: ham kod */ }
    // Eski sürümün ham kodu: ilk kullanımda bugünkü biçime çevrilir, ömrü bu andan başlar.
    const yeni: DevirKaydi = { id: crypto.randomUUID(), kod: ham.trim(), olusturma: Date.now(), sahip: null };
    if (!yeni.kod) return null;
    await a.depo.yaz(DEVIR, JSON.stringify(yeni)).catch(() => {});
    return yeni;
  };
  /** Kayıt hâlâ aynıysa (id) siler; arada yazılmış daha yeni bir devir kaydına dokunmaz. */
  const devirSil = async (id: string) => {
    const simdi = await devirOku();
    if (simdi?.id === id) await a.depo.sil(DEVIR).catch(() => {});
  };
  let devirSuruyor: Promise<GirisSonucu | null> | null = null;

  async function webDevir(): Promise<GirisSonucu | null> {
    const k = await devirOku();
    if (!k) return null;
    if (Date.now() - k.olusturma > DEVIR_OMRU) { // süre doldu: ağ yok, kayıt temizlenir
      await devirSil(k.id);
      return { devredilen: [], devirBasarisiz: true };
    }
    const s = await oturum();
    const jetonu = typeof s?.access_token === "string" && s.access_token ? s.access_token : null;
    if (!s || s.user.is_anonymous || !jetonu) return null; // henüz uygun dönüş değil; kayıt kalır
    if (k.sahip && k.sahip !== s.user.id) return null; // başka kalıcı hesap: bu kayıt onda denenmez
    if (!k.sahip) {
      const simdi = await devirOku();
      if (simdi?.id !== k.id) return null; // arada yeni bir devir başladı
      // Sahiplik yazılamazsa çağrı yapılmaz: yoksa geçici hatadan sonra kayıt sahipsiz kalır ve başka hesapta denenebilir.
      try {
        await a.depo.yaz(DEVIR, JSON.stringify({ ...k, sahip: s.user.id }));
      } catch {
        return null;
      }
      k.sahip = s.user.id;
    }
    // Çağrı, hedef hesabın o anki doğrulanmış jetonuna sabitlenir; SDK'nın değişen oturumunun örtük jetonuna düşülmez.
    const istek = ortak().rpc("hesap_devral", { p_kod: k.kod }) as unknown as {
      setHeader?: (ad: string, deger: string) => PromiseLike<{ data: unknown; error: { message?: string } | null }>;
    };
    if (typeof istek.setHeader !== "function") return { devredilen: [], devirBasarisiz: true }; // jeton sabitlenemiyor: kayıt kalır
    let data: unknown, error: { message?: string } | null;
    try {
      ({ data, error } = await istek.setHeader("Authorization", `Bearer ${jetonu}`));
    } catch {
      // ağ: kayıt kalır, aynı hesapta yeniden denenir. Arada hesap değiştiyse eski sonuç yeni oturuma dönmez.
      if ((await oturumKimligi()) !== s.user.id) return null;
      return { devredilen: [], devirBasarisiz: true };
    }
    // Yanıt döndüğünde hesap değiştiyse sonuç bu oturumda kullanılmaz; kayıt sahibine bağlı kalır.
    if ((await oturumKimligi()) !== s.user.id) return null;
    if (!error) {
      await devirSil(k.id);
      const r = data as { oyunlar: string[]; skorlar_tasindi: boolean };
      return { devredilen: r.oyunlar, skorlarTasindi: r.skorlar_tasindi };
    }
    // Kesin ret: kod geçersiz ya da süresi dolmuş. Not: önceki denemenin yanıtı kaybolmuş ve sunucu devri yapmışsa sunucu da
    // devir_kodu_gecersiz döner; bugünkü sunucu bu iki durumu ayırmaz, bu yüzden başarı sayılmaz (devirBasarisiz).
    if (/devir_kodu_gecersiz/.test(String(error.message ?? ""))) await devirSil(k.id);
    return { devredilen: [], devirBasarisiz: true }; // öteki hatalar geçici: kayıt kalır
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
      if (s?.user.is_anonymous) {
        const k: DevirKaydi = { id: crypto.randomUUID(), kod: await rpc<string>("devir_kodu_al"), olusturma: Date.now(), sahip: null };
        await a.depo.yaz(DEVIR, JSON.stringify(k));
      }
      const { error } = await sb.auth.signInWithOAuth({ provider: saglayici, options: { redirectTo: donusAdresi } });
      if (error) throw error;
    },

    /** Yönlendirmeden dönünce (oturum supabase-js tarafından kurulduktan sonra) devri tamamlar. */
    /**
     * D03: kayıt yalnız başarı, kesin `devir_kodu_gecersiz` ya da süre dolunca (30 dk) silinir; geçici hatada kalır ve aynı
     * hesapta yeniden denenir. Aynı anda gelen çağrılar tek devir işlemini paylaşır.
     */
    webDonusunuTamamla(): Promise<GirisSonucu | null> {
      if (devirSuruyor) return devirSuruyor;
      devirSuruyor = webDevir().finally(() => { devirSuruyor = null; });
      return devirSuruyor;
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
      /**
       * MD-24, göç 8440: beklenen hesap verilince okuma ve yazma hesap doğrulamalı işlevlerle yapılır; sunucu her çağrıda
       * oturumdaki kullanıcının `kim` olduğunu denetler ('hesap_degisti'). Bellek girdisi yalnız aynı `kim` için kullanılır ve
       * `kim` ile yazılır. İşlevler yoksa (göç uygulanmamış) ya da çağrı reddedilirse eski işlevlere düşülmez.
       */
      const hesapliRpc = async <R>(ad: string, arg: Record<string, unknown>): Promise<R> => {
        try { return await rpc<R>(ad, arg); }
        catch (e) {
          const m = e instanceof Error ? e.message : String(e);
          if (/could not find the function|schema cache/i.test(m)) throw new Error("kayit_hesapli_yok");
          throw e;
        }
      };
      async function birlestirHesapli(kim: string, yerel: T, birlestir: (yerel: T, uzak: T) => Birlesim<T>): Promise<Birlesim<T>> {
        for (let i = 0; i < 4; i++) {
          const bilinen = i === 0 && bulutBilinen?.dogrulandi && bulutBilinen.kim === kim ? bulutBilinen : null;
          let uzak: { veri: T; surum: number } | null;
          if (bilinen) uzak = { veri: bilinen.veri as T, surum: bilinen.surum };
          else {
            uzak = await hesapliRpc<{ veri: T; surum: number } | null>("kayit_oku_hesapli", { p_oyun: a.oyunId, p_kim: kim });
            bulutBilinen = uzak ? { kim, veri: uzak.veri, surum: uzak.surum, dogrulandi: true } : null;
          }
          const b = uzak ? birlestir(yerel, uzak.veri) : { kayit: yerel };
          if (uzak && ayniJson(b.kayit, uzak.veri)) return b; // değişmeyen kayıt yazılmaz (GC-2)
          const s = await hesapliRpc<number | null>("kayit_yaz_hesapli", { p_oyun: a.oyunId, p_veri: b.kayit, p_surum: uzak?.surum ?? 0, p_kim: kim });
          if (s != null) {
            bulutBilinen = { kim, veri: b.kayit, surum: s, dogrulandi: true };
            return b;
          }
          bulutBilinen = null;
        }
        throw new Error("kayit_cakisma");
      }
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
          if (secenek.kim !== undefined) return birlestirHesapli(secenek.kim, yerel, birlestir);
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
