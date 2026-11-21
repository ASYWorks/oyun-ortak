/**
 * Duraklatılabilir sıralama süresi (ms): aktif_ms + son nabızdan bu yana geçen (tam; 19 Kasım güvenlik B1: nabız kesmek
 * süreyi kısaltmasın). Teslimde durdu yok sayılır (dürüst oyun duraklatılmışken teslim edemez).
 * Nabız hiç gelmediyse null: oyun duvar saatini (şimdi − olusturma) yedek kullanır. Bağımlılıksız (Node testleri de yükler).
 */
export function aktifSureMs(d: { aktif_ms?: number; son_nabiz?: string | null; durdu?: boolean }, simdi: Date): number | null {
  if (!d.son_nabiz) return null;
  return Number(d.aktif_ms ?? 0) + Math.max(0, simdi.getTime() - Date.parse(d.son_nabiz));
}

/** Duraklatma etkin süreyi ve 2 dakikayı aşınca true: skora 'nabiz_boslugu' bayrağı (Şampiyon ve lig dışı, tabloda kalır). */
export const nabizBoslugu = (d: { durak_ms?: number | string | null }, aktifMs: number): boolean =>
  Number(d.durak_ms ?? 0) > Math.max(aktifMs, 120_000);
