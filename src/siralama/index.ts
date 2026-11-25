/**
 * siralama: doğrulamalı skor gönderimi (çevrimdışı kuyrukla), günlük/etkinlik tablosu, haftalık lig.
 *
 * Gönderim yalnız `dogrula-<oyun>` Edge Function'ına gider; puanı sunucu hesaplar. Ağ yoksa, oturum yenilenemediyse
 * ya da sunucu geçici hata verdiyse gönderim kuyrukta kalır ve sonra yeniden denenir (sezgi giden kutusu deseni).
 * Kalıcı ret (pencere kapandı, sürüm eski, geçersiz kayıt) kuyruktan düşer ve sonuç olarak bildirilir.
 */
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Depo } from "../kayit/index.ts";

export * from "./zaman.ts";

export interface GonderimSonucu {
  runId: string;
  /** HTTP durumu; 0 = ağ yok. */
  durum: number;
  veri: unknown;
  /** true ise kuyrukta kaldı, sonra yeniden denenecek. */
  bekliyor: boolean;
}

interface Bekleyen {
  runId: string;
  govde: Record<string, unknown>;
  eklendi: number;
  /**
   * Gönderimi yapan hesap (O15, D02): yalnız o hesabın oturumuyla gider, sonucu yalnız o oturumda uygulanır.
   * null: oturumsuz (misafir) gönderim; ilk gönderimde açılan anonim hesaba bağlanır. Kalıcı bir hesaba hiç gitmez.
   * Eski kayıtta alan yok (sahipsiz): misafir kaydı gibi işlenir, kalıcı hesaba yazılmaz.
   */
  kullanici?: string | null;
}

/** Oturumun gönderim için gereken kısmı. anonim: Supabase `user.is_anonymous` (alan yoksa false: kalıcı sayılır, güvenli taraf). */
interface OturumBilgisi { id: string; anonim: boolean; jeton: string | null }

export interface Satir {
  sira: number;
  ad: string | null;
  puan: number;
  ikincil: number | null;
  /** Profil kimliği (rastgele; kullanıcı kimliği değil). `profil(id)` ile açılır. */
  profil?: string;
  ben: boolean;
}
export interface Tablo {
  toplam: number;
  /** true: dönemin sıra ödülü yazıldı (kapanış işi çalıştı), sıra artık değişmez. Ödül işi olmayan dönemde false. */
  kapandi?: boolean;
  ben: { sira: number; ust_yuzde: number | null } | null;
  satirlar: Satir[];
}
export interface LigDurumu {
  hafta: string;
  kademe: number;
  kademe_adi: string | null;
  katildi: boolean;
  /** ikincil: eşitlikte sıralamayı belirleyen ham değer (en iyi N günün toplamı; birimi oyuna ait). Lig eşitliği 'ikincil' değilse null. */
  uyeler: { sira: number; ad: string | null; puan: number; ikincil?: number | null; profil?: string; ben: boolean }[];
  onceki: { hafta: string; sira: number | null; sonuc: "cikti" | "kaldi" | "indi"; puan: number } | null;
}

export interface LigHaftasi {
  hafta: string;
  kademe: number;
  kademe_adi: string | null;
  sira: number | null;
  sonuc: "cikti" | "kaldi" | "indi" | null;
  puan: number;
  kisi: number;
}

/** Oyuncu profili. Gizli profilde yalnız `ad` ve `gizli: true` gelir. */
export interface Profil {
  ad: string | null;
  gizli: boolean;
  ben?: boolean;
  kademe?: number;
  kademe_adi?: string | null;
  /** Bu haftaki lig sırası; ligde değilse null. */
  lig?: { sira: number; kisi: number } | null;
  /** Oyuna katılım ayı, YYYY-AA. */
  katilim?: string;
  desen?: string | null;
  /** hedef_sure / hedef_hamle: süresi / hamlesi günün hedefini aşmayan gün sayısı (yalnız puan sürümü 4 ve sonrası). */
  gunluk?: {
    cozulen: number; simdiki_seri?: number; en_uzun_seri: number; ortalama_puan: number | null;
    hedef_sure?: number; hedef_hamle?: number; yuz_ustu: number;
  };
  etkinlik?: { katildi: number; en_iyi_sira: number | null; sampiyon: number };
  oduller?: { odul: string; kazanildi: string }[];
}

export interface SiralamaAyari {
  supabase: SupabaseClient;
  oyunId: string;
  depo: Depo;
  /** Varsayılan `dogrula-<oyunId>`. */
  fonksiyon?: string;
  /**
   * Her gönderim sonucu için çağrılır (GC-1): `gonder`'in kendi sonucu, onunla birlikte giden kuyruktaki öncekiler ve
   * açılışta `bosalt` ile gidenler. `ad_gerekli`, `misafir`, `cihaz` gibi yanıtları tek yerde işlemek için.
   */
  sonuc?: (s: GonderimSonucu) => void;
  /** Bot koruması (OL-9): oturum yoksa açılan anonim girişe Turnstile jetonu. `hesapBaslat`'takiyle aynı sağlayıcı. */
  captcha?: () => Promise<string>;
}

const KUYRUK_SINIRI = 50;

/**
 * Günlük sıralamaya bu kurulumdan (uygulama ya da tarayıcı) bugün başka bir hesap girdiyse sunucu skoru sıralamaya
 * yazmaz ve `veri.durum === "cihaz"` döner; oyun bu metni gösterir. Kimlik kuruluma aittir: aynı telefondaki uygulama
 * ve tarayıcı ayrı sayılır (parmak izi çıkarılmaz).
 */
export const SIRALAMA_METINLERI = {
  tr: {
    cihaz: {
      uygulama: "Bu uygulamadan bugün başka bir hesap sıralamaya girdi. Bu sonuç bugünün sıralamasında yer almayacak.",
      tarayici: "Bu tarayıcıdan bugün başka bir hesap sıralamaya girdi. Bu sonuç bugünün sıralamasında yer almayacak.",
    },
  },
  en: {
    cihaz: {
      uygulama: "Another account has already entered today's leaderboard from this app. This result won't appear on today's leaderboard.",
      tarayici: "Another account has already entered today's leaderboard from this browser. This result won't appear on today's leaderboard.",
    },
  },
} as const;
const CIHAZ_KEY = "oyun-ortak:cihaz";
export const yenidenDenenir = (durum: number) => durum === 0 || durum === 401 || durum === 429 || durum >= 500;

/**
 * Kişisel ödül çubuğu (HK-2: 5/10/15/20/25): lig puanına göre ulaşılan kademe sayısı ve bir sonrakine kalan.
 */
export function odulCubugu(puan: number, kademeler: readonly number[]) {
  const ulasilan = kademeler.filter((k) => puan >= k).length;
  const sonraki = kademeler[ulasilan] ?? null;
  return { ulasilan, sonraki, kalan: sonraki == null ? 0 : sonraki - puan };
}

export function siralamaBaslat(a: SiralamaAyari) {
  const sb = a.supabase;
  const fn = a.fonksiyon ?? `dogrula-${a.oyunId}`;
  const KEY = `oyun-ortak:gonderim:${a.oyunId}`;
  const BEKLEME_SINIRI = 7 * 86_400_000;
  let kuyruk: Bekleyen[] | null = null;
  let bosaltiliyor: Promise<GonderimSonucu[]> | null = null;
  let cihaz: string | null = null;
  // Kurulumun rastgele kimliği (sıralamada "bu kurulumdan günde bir hesap"); kişisel veri değil, depoda kalır.
  const nabiz = async (anahtar: string, durdur = false): Promise<number> => {
    const { data, error } = await sb.schema("ortak").rpc("nabiz", { p_oyun: a.oyunId, p_anahtar: anahtar, p_durdur: durdur });
    if (error) throw new Error(error.message);
    return (data as { aktif_ms: number }).aktif_ms;
  };
  const cihazKimligi = async (): Promise<string> => {
    if (cihaz) return cihaz;
    const v = await a.depo.oku(CIHAZ_KEY).catch(() => null);
    cihaz = v && /^[0-9a-f-]{36}$/i.test(v) ? v : crypto.randomUUID();
    if (cihaz !== v) await a.depo.yaz(CIHAZ_KEY, cihaz).catch(() => {});
    return cihaz;
  };

  const yukle = async (): Promise<Bekleyen[]> => {
    if (kuyruk) return kuyruk;
    try {
      const v: unknown = JSON.parse((await a.depo.oku(KEY)) ?? "[]");
      kuyruk = Array.isArray(v) ? (v as Bekleyen[]) : [];
    } catch {
      kuyruk = [];
    }
    return kuyruk;
  };
  const oturum = async (): Promise<OturumBilgisi | null> => {
    try {
      const s = (await sb.auth.getSession()).data.session as
        | { user: { id: string; is_anonymous?: boolean }; access_token?: string } | null;
      return s ? { id: s.user.id, anonim: s.user.is_anonymous === true, jeton: typeof s.access_token === "string" && s.access_token ? s.access_token : null } : null;
    } catch {
      return null;
    }
  };
  const oturumKullanici = async (): Promise<string | null> => (await oturum())?.id ?? null;
  const sakla = () => a.depo.yaz(KEY, JSON.stringify(kuyruk ?? [])).catch(() => {});

  /**
   * Kaydın sahibine ait oturum: sahipli kayıtta oturum o hesap olmalı; sahipsiz (misafir ya da eski) kayıt yalnız oturumsuzken
   * (anonim giriş açılır) ya da anonim oturumda gider ve o anonim hesaba bağlanır. Kalıcı hesaba sahipsiz kayıt gitmez.
   * null: bu kayıt şimdi gönderilemez (kuyrukta bekler).
   */
  async function sahipOturumu(b: Bekleyen): Promise<OturumBilgisi | null | "anonim_giris"> {
    let o = await oturum();
    // Jetonsuz oturumla hiç gönderilmez: SDK'nın örtük başka oturumuna geri düşülmesin.
    if (b.kullanici) return o && o.id === b.kullanici && o.jeton ? o : null;
    if (o) {
      if (!o.anonim || !o.jeton) return null; // sahipsiz kayıt kalıcı hesaba gitmez
    } else {
      const captchaToken = a.captcha ? await a.captcha() : null;
      // captcha beklerken bir oturum açıldıysa ezilmez: kalıcıysa kayıt bekler, anonimse ona bağlanır
      const ara = await oturum();
      if (ara) {
        if (!ara.anonim || !ara.jeton) return null;
        o = ara;
      } else {
        const { data, error } = await sb.auth.signInAnonymously({ options: captchaToken ? { captchaToken } : {} });
        if (error) return "anonim_giris";
        const d = data as { session?: { user?: { id?: string } } | null; user?: { id?: string } | null } | null;
        const donen = d?.session?.user?.id ?? d?.user?.id ?? null;
        o = await oturum();
        // SDK'nın döndürdüğü kimlik ile yeniden okunan etkin anonim oturum eşleşmeli
        if (!o || !o.anonim || !o.jeton || !donen || o.id !== donen) return null;
      }
    }
    b.kullanici = o.id; // misafir kaydı bu anonim hesaba bağlanır; yeniden denemeler aynı hesapla gider
    await sakla();
    // sahiplik yazılırken hesap değiştiyse gönderilmez (kayıt anonim sahibine bağlı kalır)
    const son = await oturum();
    return son && son.id === o.id && son.jeton ? son : null;
  }

  type Cagri = { tur: "bekle" } | { tur: "sonuc"; durum: number; veri: unknown } | { tur: "sustur" };

  async function cagir(b: Bekleyen): Promise<Cagri> {
    try {
      const kimlik = await cihazKimligi(); // cihaz kimliği yüklenirken hesap değişebilir: sahiplik bundan sonra denetlenir
      const o = await sahipOturumu(b);
      if (o === "anonim_giris") return { tur: "sonuc", durum: 0, veri: { error: "anonim_giris" } };
      if (!o) return { tur: "bekle" };
      // Gönderim doğrulanmış oturumun jetonuna sabitlenir; yanıt beklerken oturum değişse de istek sahibi adına gider.
      const { data, error } = await sb.functions.invoke(fn, {
        body: { ...b.govde, runId: b.runId, cihaz: kimlik },
        headers: { Authorization: `Bearer ${o.jeton}` },
      });
      let r: { durum: number; veri: unknown };
      if (!error) r = { durum: 200, veri: data };
      else {
        const yanit = (error as { context?: unknown }).context;
        if (yanit instanceof Response) {
          let veri: unknown = null;
          try { veri = await yanit.json(); } catch { veri = null; }
          r = { durum: yanit.status, veri };
        } else r = { durum: 0, veri: { error: "ag" } };
      }
      // Yanıt döndüğünde hesap değişmişse sonuç yeni oturumda uygulanmaz; kayıt kuyrukta kalır ve sahibi dönünce
      // aynı runId ile yeniden gider (sunucu tek skor üretir, gerçek sonuç o oturumda işlenir).
      if ((await oturumKullanici()) !== o.id) return { tur: "sustur" };
      return { tur: "sonuc", ...r };
    } catch {
      return { tur: "sonuc", durum: 0, veri: { error: "ag" } };
    }
  }

  async function bosalt(): Promise<GonderimSonucu[]> {
    if (bosaltiliyor) return bosaltiliyor;
    bosaltiliyor = (async () => {
      const q = await yukle();
      const sonuclar: GonderimSonucu[] = [];
      for (const b of [...q]) {
        const r = await cagir(b);
        if (r.tur === "bekle" && Date.now() - b.eklendi > BEKLEME_SINIRI) {
          // Sahibi 7 gündür dönmeyen ya da kalıcı hesapta bekleyen misafir kaydı: sunucu kapanmış güne zaten almaz, kuyruk şişmesin.
          kuyruk = (kuyruk ?? []).filter((x) => x.runId !== b.runId);
          await sakla();
          continue;
        }
        if (r.tur === "bekle" || r.tur === "sustur") continue; // başka hesabın kaydı ya da hesap değişti: kuyrukta bekler
        const bekliyor = yenidenDenenir(r.durum);
        const s = { runId: b.runId, durum: r.durum, veri: r.veri, bekliyor };
        sonuclar.push(s);
        try {
          a.sonuc?.(s);
        } catch {
          // oyunun işleyicisindeki hata kuyruğu durdurmaz
        }
        if (bekliyor) break; // ağ yoksa sıradakiler de gitmez; sırayı koru
        kuyruk = (kuyruk ?? []).filter((x) => x.runId !== b.runId);
        await sakla();
      }
      return sonuclar;
    })();
    try {
      return await bosaltiliyor;
    } finally {
      bosaltiliyor = null;
    }
  }

  return {
    /**
     * Gönderimi kuyruğa ekler ve kuyruğu boşaltmayı dener. `runId` her gönderimde bir kez üretilir;
     * aynı gönderimin yeniden denenmesi sunucuda tek skor üretir.
     */
    async gonder(govde: Record<string, unknown>): Promise<GonderimSonucu> {
      const q = await yukle();
      const b: Bekleyen = { runId: crypto.randomUUID(), govde, eklendi: Date.now(), kullanici: await oturumKullanici() };
      q.push(b);
      if (q.length > KUYRUK_SINIRI) q.splice(0, q.length - KUYRUK_SINIRI);
      await sakla();
      const ilk = await bosalt();
      let s = ilk.find((x) => x.runId === b.runId);
      // Süren bir boşaltmaya denk geldiyse o tur bu gönderimi görmedi: bir tur daha (ağ yoksa değil).
      if (!s && !ilk.some((x) => x.bekliyor) && (kuyruk ?? []).some((x) => x.runId === b.runId))
        s = (await bosalt()).find((x) => x.runId === b.runId);
      return s ?? { runId: b.runId, durum: 0, veri: null, bekliyor: true };
    },
    /** Uygulama açılışında, ön plana dönüşte ve ağ gelince çağrılır. */
    bosalt,
    bekleyenSayisi: async () => (await yukle()).length,

    async tablo(tur: "gunluk" | "etkinlik", donem: string, o: { ilk?: number; cevre?: number } = {}): Promise<Tablo> {
      const { data, error } = await sb.schema("ortak").rpc("siralama", {
        p_oyun: a.oyunId, p_tur: tur, p_donem: donem, p_ilk: o.ilk ?? 10, p_cevre: o.cevre ?? 3,
      });
      if (error) throw new Error(error.message);
      return data as Tablo;
    },

    async lig(): Promise<LigDurumu> {
      const { data, error } = await sb.schema("ortak").rpc("lig_durumu", { p_oyun: a.oyunId });
      if (error) throw new Error(error.message);
      return data as LigDurumu;
    },

    /**
     * Duraklatılabilir süre (ADIL_PUAN §1.2): bulmaca ekranı görünürken çağrılır; ilk çağrı denemeyi açar.
     * Dönüş: sunucunun saydığı aktif süre (ms). Anahtar, dogrula-<oyun>'un deneme anahtarıyla aynı olmalı.
     * `nabiz(anahtar, true)` durdur nabzıdır: o ana kadarki süre sayılır, sayaç durur.
     */
    nabiz,

    /**
     * Nabız döngüsü: hemen bir nabız, sonra `aralikMs`'de bir (varsayılan 10 sn); sayfa gizliyken gönderilmez,
     * görünür olunca hemen gönderilir; gizlenince durdur nabzı gider. Duraklatınca ya da bulmaca bitince dönen işlev
     * çağrılır: döngü durur ve durdur nabzı gider (duraklatma süreye eklenmez).
     * Ağ hatası sessizce yutulur: 90 sn'ye kadar boşluk bir sonrakine tam eklenir, daha uzunu duraklatma sayılır.
     * Nabız sayan başka bir istek (ör. Halka kontrolü) gidince `dokundu()` çağrılır: son `aralikMs` içinde böyle bir
     * istek gittiyse döngü o turda nabız göndermez (yük, 19 Kasım).
     */
    nabizBaslat(anahtar: string, aralikMs = 10_000): (() => void) & { dokundu: () => void } {
      const belge = (globalThis as { document?: Document }).document;
      let dokunus = 0; // nabız sayan son başka istek
      const gonder = (zorla = false) => {
        if (belge?.visibilityState === "hidden") return;
        if (!zorla && Date.now() - dokunus < aralikMs) return;
        void nabiz(anahtar).catch(() => {});
      };
      // Durdur nabzı: o ana kadarki süre sayılır, sayaç durur; devam nabzı süre eklemeden yeniden başlatır (duraklatma cezasız).
      const durdur = () => void nabiz(anahtar, true).catch(() => {});
      gonder(true);
      const t = setInterval(() => gonder(), aralikMs);
      const gorunur = () => { if (belge?.visibilityState === "visible") gonder(true); else durdur(); };
      belge?.addEventListener("visibilitychange", gorunur);
      const bitir = () => { clearInterval(t); belge?.removeEventListener("visibilitychange", gorunur); durdur(); };
      return Object.assign(bitir, { dokundu: () => { dokunus = Date.now(); } });
    },

    /** Oyuncu profili (girişsiz de çağrılabilir; dakikada 30). Bulunamazsa null. */
    async profil(id: string): Promise<Profil | null> {
      const { data, error } = await sb.schema("ortak").rpc("profil", { p_oyun: a.oyunId, p_profil: id });
      if (error) throw new Error(error.message);
      return data as Profil | null;
    },

    /** Kendi profil ayarı (girişli). Verilmeyen alan değişmez; `desen: ""` deseni kaldırır. Oyuncu satırı yoksa null. */
    async profilAyari(o: { gizli?: boolean; desen?: string }): Promise<{ profil: string; gizli: boolean; desen: string | null } | null> {
      const { data, error } = await sb.schema("ortak").rpc("profil_ayari", {
        p_oyun: a.oyunId, p_gizli: o.gizli ?? null, p_desen: o.desen ?? null,
      });
      if (error) throw new Error(error.message);
      return data;
    },

    /** Geçmiş lig haftaları (HK-13), yeniden eskiye, en çok 26. Misafirde boş. */
    async ligGecmisi(haftaSayisi = 8): Promise<LigHaftasi[]> {
      const { data, error } = await sb.schema("ortak").rpc("lig_gecmisi", { p_oyun: a.oyunId, p_hafta_sayisi: haftaSayisi });
      if (error) throw new Error(error.message);
      return data as LigHaftasi[];
    },
  };
}

export type Siralama = ReturnType<typeof siralamaBaslat>;
