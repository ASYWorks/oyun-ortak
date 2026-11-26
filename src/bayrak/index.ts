/**
 * bayrak: sunucu bayraklarının cihazda saklanması (KY-3; ÖG-58, ÖG-61, O29, O30; docs/ONIZLEME.md). Kapı app/src/bayrak.ts'ten.
 *
 * İlk çizim ağı beklemez; o arada saklı bayraklar geçer. İki ayrı kayıt: halka açık (testçi alanı hiç yazılmaz, testçinin boş
 * kapali listesi de yazılmaz) ve hesap sahibine bağlı (`{ sahip, b }`, yalnız aynı hesap kimliğiyle okunur; aynı testçi çevrimdışı
 * da testçi kalır). Bilinmeyen durumda önizleme varsayılır: çevrimiçi özellikler kapalı, vitrin sırası uygulanır.
 * Geç ya da başka hesaba ait yanıt uygulanmaz. DOM'suz; depo eşzamanlıdır (ilk çizim beklemesin diye localStorage).
 */

export type Bayraklar = { kapali?: string[]; duyuru?: string; onizleme?: boolean; testci?: boolean; yayin_tarihi?: string; asgari_surum?: string };
export const CEVRIMICI_OZELLIKLER = ["gunluk", "siralama", "etkinlik", "lig", "turnuva", "duello"];
export interface BayrakDepo { al(k: string): string | null; yaz(k: string, v: string): void; sil(k: string): void }

const nesne = (x: unknown): x is Record<string, unknown> => !!x && typeof x === "object" && !Array.isArray(x);

/** Yalnız tanınan ve doğru tipli alanlar; testçi alanı halka açık bayrakta yoktur. Biçimi bozuksa null. */
function temizle(x: unknown, testciDahil: boolean): Bayraklar | null {
  if (!nesne(x)) return null;
  if (x.kapali !== undefined && !(Array.isArray(x.kapali) && x.kapali.every((k) => typeof k === "string"))) return null;
  const b: Bayraklar = {};
  if (Array.isArray(x.kapali)) b.kapali = [...(x.kapali as string[])];
  if (typeof x.onizleme === "boolean") b.onizleme = x.onizleme;
  if (typeof x.yayin_tarihi === "string") b.yayin_tarihi = x.yayin_tarihi;
  if (typeof x.duyuru === "string") b.duyuru = x.duyuru;
  if (typeof x.asgari_surum === "string") b.asgari_surum = x.asgari_surum;
  if (testciDahil && x.testci === true) b.testci = true;
  return b;
}

/** İsteği açan hesap hâlâ etkin mi: bütün güncel kaynaklar (bellekteki oturum, cihazdaki gerçek oturum; misafirde '') aynı kimliği
 *  göstermeli. Başka sekme cihazdaki oturumu değiştirmiş olabilir. */
export const kimlikUyar = (istekId: string, simdi: (string | null)[]) => simdi.every((k) => k === istekId);

/**
 * Oyunun bayrak deposu. Anahtarlar `<oyunId>:bayraklar:genel` ve `:hesap`.
 * `varsayilanKapali`: bayrak bilinmezken kapalı sayılan özellikler (varsayılan CEVRIMICI_OZELLIKLER).
 * `eskiAnahtar`: oyunun eski sahipsiz kaydı varsa açılışta silinir (testçi olabilir, güvenilmez).
 */
export function bayrakDeposu(d: BayrakDepo, oyunId: string, o: { varsayilanKapali?: string[]; eskiAnahtar?: string } = {}) {
  const GENEL = `${oyunId}:bayraklar:genel`, HESAP = `${oyunId}:bayraklar:hesap`;
  const oku = (k: string): unknown => { try { return JSON.parse(d.al(k) ?? "null"); } catch { return null; } };
  /** Henüz doğrulanmamış durum: önizleme, çevrimiçi özellikler kapalı. */
  const bilinmeyen = (): Bayraklar => ({ onizleme: true, kapali: [...(o.varsayilanKapali ?? CEVRIMICI_OZELLIKLER)] });
  return {
    bilinmeyen,
    /** Açılıştaki bayraklar (ağsız). id: cihazdaki oturumun hesap kimliği, misafirde ''. */
    ilkBayraklar(id: string): Bayraklar {
      if (o.eskiAnahtar) { try { d.sil(o.eskiAnahtar); } catch { /* depo yok */ } }
      if (id) {
        const h = oku(HESAP);
        if (nesne(h) && h.sahip === id) { const b = temizle(h.b, true); if (b) return b; }
      }
      return temizle(oku(GENEL), false) ?? bilinmeyen();
    },
    /** Sunucu yanıtı geldi. İsteği açan hesap artık geçerli değilse null (uygulanmaz, saklanmaz). Hesap yanıtı sahibine bağlı
     *  saklanır; testçi olmayan yanıt halka açık kayda da yazılır. Misafir yanıtı testçi yetkisi taşıyamaz. */
    cevapKaydet(istekId: string, simdi: (string | null)[], ham: unknown): Bayraklar | null {
      if (!kimlikUyar(istekId, simdi)) return null;
      if (!istekId && nesne(ham) && ham.testci === true) return null; // misafire testçi yanıtı biçim dışı
      const b = temizle(ham ?? {}, !!istekId);
      if (!b) return null;
      try {
        if (istekId) d.yaz(HESAP, JSON.stringify({ sahip: istekId, b }));
        if (!b.testci) d.yaz(GENEL, JSON.stringify(b));
      } catch { /* depo yok: bu açılışta geçerli */ }
      return b;
    },
  };
}

/** Tarayıcı deposu (yoksa her şey sessizce yok sayılır). */
export const yerelDepo: BayrakDepo = {
  al: (k) => { try { return localStorage.getItem(k); } catch { return null; } },
  yaz: (k, v) => { try { localStorage.setItem(k, v); } catch { /* yok */ } },
  sil: (k) => { try { localStorage.removeItem(k); } catch { /* yok */ } },
};
