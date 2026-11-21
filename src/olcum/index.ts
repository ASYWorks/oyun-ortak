/**
 * olcum: olayları PostHog'a (AB bulutu) gönderir. SDK yok, düz fetch; web, Capacitor ve Expo'da aynı kod.
 *
 * - Olay adı çekirdek listede ya da oyunun `uzantiOlaylar` listesinde olmalı; değilse düşer.
 * - Özellikler yalnız basit türler (metin ≤200, sonlu sayı, mantıksal, null); kişisel veri konmaz.
 * - Kuyruk depoda kalır (en çok 500 olay, dolunca en eskisi düşer); ağ gelince toplu gider.
 * - PostHog kalıcı hata (4xx) dönerse ölçüm bu oturumda sessizce durur; oyun hiçbir zaman etkilenmez.
 */
import type { Depo } from "../kayit/index.ts";

export const CEKIRDEK_OLAYLAR = [
  "oturum_basla",
  "seviye_basla",
  "seviye_bitir",
  "seviye_kaybet",
  "gunluk_basla",
  "gunluk_bitir",
  "hesap_bagla",
  "satin_alma_goster",
  "satin_alma_basla",
  "satin_alma_bitir",
  "satin_alma_iptal",
  "hata",
  "geri_bildirim",
] as const;

export type Ozellikler = Record<string, string | number | boolean | null>;

export interface OlcumAyari {
  oyunId: string;
  /** Oyunun sürümü (ör. "1.4.0"). */
  surum: string;
  platform: "web" | "android" | "ios";
  /** PostHog proje anahtarı (herkese açık anahtar, gizli değil). Boşsa ölçüm kapalı. */
  anahtar: string;
  /** Kayıt paketinden cihaz kimliği. */
  cihaz: string;
  depo: Depo;
  /** Oyuna özgü olay adları (KM-10, KH-8, EN-11, HK-6). */
  uzantiOlaylar?: readonly string[];
  adres?: string;
  /** Kuyruk bu sayıya ulaşınca hemen gönderilir. */
  topluSinir?: number;
  /** Otomatik gönderim aralığı (ms); 0 kapatır. */
  aralik?: number;
  fetch?: typeof fetch;
  simdi?: () => Date;
}

interface Kuyruktaki {
  event: string;
  /** `$exception_list` iç içe nesne taşır; öteki olaylarda yalnız basit türler. */
  properties: Record<string, unknown> & { distinct_id: string };
  timestamp: string;
}

export interface Olcum {
  olay(ad: string, ozellik?: Ozellikler): void;
  /**
   * Hata takibi (OL-4): PostHog `$exception` biçiminde kuyruğa koyar (Error tracking ekranında gruplanır).
   * Aynı ileti oturumda bir kez, oturumda en çok 20 hata gider. Ölçüm kapalıysa gitmez.
   */
  hata(e: unknown, ozellik?: Ozellikler & { elle?: boolean }): void;
  /**
   * Oyuncunun açıkça gönderdiği tek olay (geri bildirim): ölçüm kapalı olsa da gider, ama cihaz kimliği olmadan
   * (her gönderimde yeni rastgele kimlik) ve kuyruğa girmeden hemen.
   */
  adsizOlay(ad: string, ozellik?: Ozellikler): Promise<void>;
  /** Tek olayı kuyruğa koymadan hemen gönderir (cihaz kimliğiyle); ağ yoksa ya da reddedilirse "gonderilemedi" fırlatır. Ölçüm kapalıysa gitmez. */
  hemenOlay(ad: string, ozellik?: Ozellikler): Promise<void>;
  /** Oyuncunun ölçüm tercihi (ayarlarda "Kullanım ölçümü"). Varsayılan açık; kapalıyken olay gitmez, kuyruk silinir. */
  acik(): boolean;
  ayarla(acik: boolean): Promise<void>;
  /** Kuyruğu gönderir; asla hata atmaz. */
  gonder(): Promise<void>;
  /** Zamanlayıcıyı durdurur. */
  kapat(): void;
  /** Test ve tanıtım sayfası için. */
  readonly kuyruk: readonly Kuyruktaki[];
  readonly durdu: boolean;
}

const KUYRUK_SINIRI = 500;
const AD = /^[a-z][a-z0-9_]{0,39}$/;
const OZELLIK_SINIRI = 30;

export function temizOzellikler(o: Ozellikler | undefined): Ozellikler {
  const r: Ozellikler = {};
  let n = 0;
  for (const [k, v] of Object.entries(o ?? {})) {
    if (n >= OZELLIK_SINIRI || !AD.test(k)) continue;
    if (v === null || typeof v === "boolean") r[k] = v;
    else if (typeof v === "number" && Number.isFinite(v)) r[k] = v;
    else if (typeof v === "string") r[k] = v.slice(0, 200);
    else continue;
    n++;
  }
  return r;
}

const HATA_SINIRI = 20;

/** Hata metninden kişisel veri ve jeton ayıklar: adresin ?… ve #… kısmı (OAuth dönüşü #access_token taşır), e-posta, uzun jeton. */
export const ayikla = (m: string): string =>
  m.replace(/(https?:\/\/[^\s?#)]*)[?#][^\s)]*/g, "$1")
    .replace(/[^\s@]+@[^\s@]+\.[a-z]{2,}/gi, "<eposta>")
    .replace(/[A-Za-z0-9_\-.+/=]{24,}/g, "<jeton>");

/** Chrome ("at f (url:1:2)") ve Firefox/Safari ("f@url:1:2") yığın satırlarını PostHog çerçevelerine çevirir; en içteki çerçeve sonda. */
export function yiginCoz(yigin: string | undefined): { platform: string; filename: string; function: string; lineno: number; colno: number; in_app: boolean }[] {
  const cerceveler = [];
  for (const satir of (yigin ?? "").split("\n").slice(0, 50)) {
    const m = /^\s*at (?:(.+?) \()?(.+?):(\d+):(\d+)\)?\s*$/.exec(satir) ?? /^\s*(.*?)@(.+?):(\d+):(\d+)\s*$/.exec(satir);
    if (!m) continue;
    cerceveler.push({ platform: "web:javascript", filename: m[2]!.replace(/[?#].*$/, ""), function: m[1] || "?", lineno: Number(m[3]), colno: Number(m[4]), in_app: true });
  }
  return cerceveler.reverse();
}

export async function olcumBaslat(a: OlcumAyari): Promise<Olcum> {
  const izinli = new Set<string>([...CEKIRDEK_OLAYLAR, ...(a.uzantiOlaylar ?? [])]);
  const adres = (a.adres ?? "https://eu.i.posthog.com").replace(/\/$/, "");
  const f = a.fetch ?? globalThis.fetch.bind(globalThis);
  const simdi = a.simdi ?? (() => new Date());
  const KEY = `oyun-ortak:olcum:${a.oyunId}`;
  const test = /^t-([a-z0-9]+)-/.exec(a.cihaz)?.[1] ?? null;
  let durdu = !a.anahtar;
  let gonderiliyor: Promise<void> | null = null;
  const IZIN = `oyun-ortak:olcum-izin:${a.oyunId}`;
  let acik = (await a.depo.oku(IZIN).catch(() => null)) !== "kapali";

  let kuyruk: Kuyruktaki[] = [];
  try {
    const ham = await a.depo.oku(KEY);
    const v: unknown = ham ? JSON.parse(ham) : [];
    if (Array.isArray(v)) kuyruk = v.slice(-KUYRUK_SINIRI);
  } catch {
    kuyruk = [];
  }

  const sakla = () => {
    a.depo.yaz(KEY, JSON.stringify(kuyruk)).catch(() => {});
  };

  const gonder = (): Promise<void> => {
    if (durdu || !acik || kuyruk.length === 0) return Promise.resolve();
    if (gonderiliyor) return gonderiliyor;
    const parti = kuyruk.slice(0, 100);
    gonderiliyor = (async () => {
      try {
        const r = await f(`${adres}/batch/`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ api_key: a.anahtar, batch: parti }),
          keepalive: true,
        });
        if (r.ok) {
          kuyruk = kuyruk.slice(parti.length);
          sakla();
        } else if (r.status >= 400 && r.status < 500 && r.status !== 429) {
          // Anahtar yanlış, kota kapalı ya da istek reddedildi: tekrar etmenin anlamı yok.
          durdu = true;
          kuyruk = [];
          sakla();
        }
      } catch {
        /* ağ yok: kuyrukta kalır */
      } finally {
        gonderiliyor = null;
      }
    })();
    return gonderiliyor;
  };

  /** Kuyruksuz tek gönderim; başarısızsa "gonderilemedi". adsiz: cihaz kimliği yerine her seferinde yeni kimlik. */
  const tekGonder = async (ad: string, ozellik: Ozellikler | undefined, adsiz: boolean): Promise<void> => {
    if (!a.anahtar || !izinli.has(ad)) return;
    const properties = adsiz
      ? { ...temizOzellikler(ozellik), distinct_id: crypto.randomUUID(), $process_person_profile: false,
          oyun_id: a.oyunId, surum: a.surum, platform: a.platform, test, adsiz: true }
      : { ...temizOzellikler(ozellik), distinct_id: a.cihaz, oyun_id: a.oyunId, surum: a.surum, platform: a.platform, test };
    let r: Response;
    try {
      r = await f(`${adres}/batch/`, { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ api_key: a.anahtar, batch: [{ event: ad, properties, timestamp: simdi().toISOString() }] }),
        keepalive: true });
    } catch {
      throw new Error("gonderilemedi");
    }
    if (!r.ok) throw new Error("gonderilemedi");
  };

  const zamanlayici =
    (a.aralik ?? 30_000) > 0 ? setInterval(() => void gonder(), a.aralik ?? 30_000) : undefined;
  (zamanlayici as { unref?: () => void } | undefined)?.unref?.();

  let hataSayisi = 0;
  const gorulen = new Set<string>();

  return {
    hata(e, ozellik) {
      if (durdu || !acik || hataSayisi >= HATA_SINIRI) return;
      const h = e instanceof Error ? e : new Error(String(e));
      const deger = ayikla(String(h.message)).slice(0, 300);
      if (gorulen.has(h.name + deger)) return;
      gorulen.add(h.name + deger);
      hataSayisi++;
      const { elle, ...ek } = ozellik ?? {};
      kuyruk.push({
        event: "$exception",
        properties: {
          ...temizOzellikler(ek),
          distinct_id: a.cihaz,
          oyun_id: a.oyunId,
          surum: a.surum,
          platform: a.platform,
          test,
          $exception_list: [{
            type: h.name || "Error",
            value: deger,
            mechanism: { handled: !!elle, synthetic: !(e instanceof Error) },
            stacktrace: { type: "raw", frames: yiginCoz(h.stack) },
          }],
        },
        timestamp: simdi().toISOString(),
      });
      if (kuyruk.length > KUYRUK_SINIRI) kuyruk = kuyruk.slice(-KUYRUK_SINIRI);
      sakla();
      void gonder();
    },
    olay(ad, ozellik) {
      if (durdu || !acik || !izinli.has(ad)) return;
      kuyruk.push({
        event: ad,
        properties: {
          ...temizOzellikler(ozellik),
          distinct_id: a.cihaz,
          oyun_id: a.oyunId,
          surum: a.surum,
          platform: a.platform,
          test,
        },
        timestamp: simdi().toISOString(),
      });
      if (kuyruk.length > KUYRUK_SINIRI) kuyruk = kuyruk.slice(-KUYRUK_SINIRI);
      sakla();
      if (kuyruk.length >= (a.topluSinir ?? 20)) void gonder();
    },
    adsizOlay: (ad, ozellik) => tekGonder(ad, ozellik, true),
    hemenOlay: (ad, ozellik) => (acik ? tekGonder(ad, ozellik, false) : Promise.resolve()),
    acik: () => acik,
    async ayarla(v) {
      acik = v;
      if (!v) {
        kuyruk = [];
        sakla();
      }
      await a.depo.yaz(IZIN, v ? "acik" : "kapali").catch(() => {});
    },
    gonder,
    kapat: () => clearInterval(zamanlayici),
    get kuyruk() {
      return kuyruk;
    },
    get durdu() {
      return durdu;
    },
  };
}
