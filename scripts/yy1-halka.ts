// YY-1: Halka yayın öncesi temizlik (kurucu 17 Kasım). Ön gösterim kayıtları silinir.
// Yalnız yayın gününden (Y, İstanbul 00:00) önce oluşmuş satırlara dokunur: geç koşulsa bile yayın verisi silinmez.
//   PG_URL=... Y=2026-12-01 node scripts/yy1-halka.ts          → kuru: sayar, geri alır
//   PG_URL=... Y=2026-12-01 node scripts/yy1-halka.ts uygula   → siler (canlıda kurucu onayıyla)
// Seviye ilerlemesine dokunulmaz (kurucu 17 Kasım, seçenek a): yeniden üretimle SEVIYE_SURUMU 2 olunca istemcide zaten sıfırlandı.
// Dokunulmayanlar: oyuncular (adlar), haklar/ödemeler, kozmetik ödüller, bulut kayıtları.
import postgres from "postgres";

const Y = process.env.Y ?? "";
if (!/^\d{4}-\d{2}-\d{2}$/.test(Y)) throw new Error("Y=YYYY-AA-GG");
const uygula = process.argv[2] === "uygula";
const sql = postgres(process.env.PG_URL!, { max: 1, prepare: false });

class GeriAl extends Error {}
try {
  await sql.begin(async (tx) => {
    const say = async (ad: string, q: Promise<unknown[]>) => console.log(ad.padEnd(28), (await q).length);
    await say("skorlar", tx`delete from ortak.skorlar where oyun_id = 'halka' and olusturma < (${Y}::text::date::timestamp at time zone 'Europe/Istanbul') returning 1`);
    await say("denemeler", tx`delete from ortak.denemeler where oyun_id = 'halka' and olusturma < (${Y}::text::date::timestamp at time zone 'Europe/Istanbul') returning 1`);
    await say("kurulum_gunluk (cihaz kuralı)", tx`delete from ortak.kurulum_gunluk where oyun_id = 'halka' and olusturma < (${Y}::text::date::timestamp at time zone 'Europe/Istanbul') returning 1`);
    await say("lig_gruplari (+ üyeler)", tx`delete from ortak.lig_gruplari where oyun_id = 'halka' and olusturma < (${Y}::text::date::timestamp at time zone 'Europe/Istanbul') returning 1`);
    if (!uygula) throw new GeriAl();
  });
  console.log("uygulandı");
} catch (e) {
  if (!(e instanceof GeriAl)) throw e;
  console.log("kuru koşu: geri alındı");
} finally {
  await sql.end();
}
