/**
 * his: oyun hissi yardımcıları (kurucu 26 Kasım; OYUN_DENETIMI A32–A35, `docs/arastirma/arayuz-ve-uretim-kararlari-2026-11-26.md`).
 *
 * Yalnız `transform` ve `opacity` hareketlendirilir (Web Animations API, birleştirici iş parçacığında; TBT'ye yük bindirmez).
 * Kütüphane yok. Görünümü (renk, süre, eğri) oyun kendi token'larıyla verir; burada yalnız hareketin biçimi var.
 * Hareket azaltma açıkken her hareketin hareketsiz karşılığı çalışır (A35): titreme ve esneme yerine kısa bir sınıf
 * (`his-hata`, `his-dogru`) eklenir; oyun bu sınıflara çerçeve ya da ton verir. Bilgi kaybolmaz.
 */

export type Sure = { kisa: number; orta: number; uzun: number };
/** Varsayılan süreler (ms). Oyun kendi token'larıyla `hisAyarla` üzerinden değiştirir (A34). */
let SURE: Sure = { kisa: 90, orta: 180, uzun: 320 };
let EGRI = { cikis: "cubic-bezier(0.2, 0.8, 0.2, 1)", yay: "cubic-bezier(0.3, 1.4, 0.5, 1)" };
let azaltZorla: boolean | null = null;

/** Oyun süre ve eğri token'larını ve oyun içi "Hareketi azalt" ayarını verir (null: sistem ayarına uy). */
export function hisAyarla(o: { sure?: Partial<Sure>; egri?: Partial<typeof EGRI>; hareketiAzalt?: boolean | null }) {
  if (o.sure) SURE = { ...SURE, ...o.sure };
  if (o.egri) EGRI = { ...EGRI, ...o.egri };
  if (o.hareketiAzalt !== undefined) azaltZorla = o.hareketiAzalt;
}

/** Oyun içi ayar ya da sistemin `prefers-reduced-motion` tercihi. */
export function hareketAzaltildi(): boolean {
  if (azaltZorla !== null) return azaltZorla;
  return typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/** Hareket azaltmada ya da animasyon desteklenmezse: sınıfı kısa süre ekle. */
function sinifla(el: Element, sinif: string, sure: number): Promise<void> {
  el.classList.add(sinif);
  return new Promise((r) => setTimeout(() => { el.classList.remove(sinif); r(); }, sure));
}

function oynat(el: Element, kare: Keyframe[], sure: number, egri: string, yedekSinif: string): Promise<void> {
  if (hareketAzaltildi() || typeof (el as HTMLElement).animate !== "function") return sinifla(el, yedekSinif, Math.max(sure, SURE.orta));
  return (el as HTMLElement).animate(kare, { duration: sure, easing: egri }).finished.then(() => undefined, () => undefined);
}

/** Doğru hamle: öğe kısa esner (1 → olcek → 1). */
export const esne = (el: Element, olcek = 1.08) =>
  oynat(el, [{ transform: "scale(1)" }, { transform: `scale(${olcek})` }, { transform: "scale(1)" }], SURE.orta, EGRI.yay, "his-dogru");

/** Yanlış hamle: yalnız o öğe yatay titrer (kamera sarsıntısı yerine yerel tepki). */
export const titre = (el: Element, genlik = 4) =>
  oynat(el, [0, -genlik, genlik, -genlik / 2, genlik / 2, 0].map((x) => ({ transform: `translateX(${x}px)` })), SURE.uzun, "linear", "his-hata");

/** Bitiş dalgası: öğeler sırayla (aralik ms) esner. Hareket azaltmada hepsi birlikte sınıf alır. */
export async function dalga(ogeler: Iterable<Element>, aralik = 30, olcek = 1.06): Promise<void> {
  const liste = [...ogeler];
  if (hareketAzaltildi()) { await Promise.all(liste.map((el) => sinifla(el, "his-dogru", SURE.orta))); return; }
  await Promise.all(liste.map((el, i) => new Promise<void>((r) => setTimeout(() => esne(el, olcek).then(r), i * aralik))));
}

/**
 * Ses, görüntü ve titreşimi aynı karede başlatır (A32). `ses` oyunun kendi çalma işlevi; `titresim` ms ya da desen
 * (cihazda yoksa sessizce atlanır; oyun ayarında kapalıysa oyun undefined verir).
 */
export function hisVer(o: { el?: Element; tur: "dogru" | "yanlis"; ses?: () => void; titresim?: number | number[] }): Promise<void> {
  o.ses?.();
  if (o.titresim !== undefined && typeof navigator !== "undefined" && "vibrate" in navigator) {
    try { navigator.vibrate(o.titresim); } catch { /* yok */ }
  }
  if (!o.el) return Promise.resolve();
  return o.tur === "dogru" ? esne(o.el) : titre(o.el);
}

/**
 * Parçacık: tek canvas ve nesne havuzu (DOM öğesi üretmez). Hareket azaltmada çalışmaz. `renkler` oyunun malzeme
 * renkleri; genel yıldız ve konfeti yerine oyunun kendi parçası (kâğıt kırpıntısı, toz) için `ciz` verilebilir.
 */
export function parcacik(
  canvas: HTMLCanvasElement,
  x: number,
  y: number,
  o: { adet?: number; renkler?: string[]; sure?: number; ciz?: (c: CanvasRenderingContext2D, renk: string, boy: number) => void } = {},
): Promise<void> {
  const c = canvas.getContext("2d");
  if (!c || hareketAzaltildi()) return Promise.resolve();
  const adet = Math.min(o.adet ?? 24, 80), sure = o.sure ?? SURE.uzun * 2, renkler = o.renkler ?? ["currentColor"];
  const p = Array.from({ length: adet }, (_, i) => {
    const a = (i / adet) * Math.PI * 2 + Math.random() * 0.5, h = 1.5 + Math.random() * 2.5;
    return { x, y, vx: Math.cos(a) * h, vy: Math.sin(a) * h - 1.5, boy: 3 + Math.random() * 3, renk: renkler[i % renkler.length]! };
  });
  const t0 = performance.now();
  return new Promise((bitti) => {
    const kare = (t: number) => {
      const k = (t - t0) / sure;
      c.clearRect(0, 0, canvas.width, canvas.height);
      if (k >= 1) { bitti(); return; }
      c.globalAlpha = 1 - k;
      for (const q of p) {
        q.x += q.vx; q.y += q.vy; q.vy += 0.12;
        c.save(); c.translate(q.x, q.y);
        if (o.ciz) o.ciz(c, q.renk, q.boy); else { c.fillStyle = q.renk; c.fillRect(-q.boy / 2, -q.boy / 2, q.boy, q.boy); }
        c.restore();
      }
      requestAnimationFrame(kare);
    };
    requestAnimationFrame(kare);
  });
}
