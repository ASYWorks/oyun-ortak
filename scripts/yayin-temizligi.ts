// Yayın günü: önizlemeden çıkış (göç 8280, kurucu 22 Kasım). Önizlemede günlük/lig/etkinlik yalnız testçilere açıktı; yayın
// gününden (Y, İstanbul 00:00) önce oluşmuş ortak skor, deneme, kurulum ve lig satırları silinir, ayarlar.yayin 'acik' olur.
//   PG_URL=... OYUN=koz Y=2027-01-15 node scripts/yayin-temizligi.ts          → kuru: sayar, geri alır
//   PG_URL=... OYUN=koz Y=2027-01-15 node scripts/yayin-temizligi.ts uygula   → uygular (canlıda kurucu onayıyla)
// Dokunulmayanlar: oyuncular (adlar), haklar/ödemeler, ödüller, bulut kayıtları, oyunun kendi şeması.
// Oyuna özgü tablolar (ör. halka.etkinlik_cozumler, sezgi.attempts) oyunun kendi yayın günü adımıdır (Halka: yy1-halka.ts).
import postgres from "postgres";

const OYUN = process.env.OYUN ?? "";
const Y = process.env.Y ?? "";
if (!/^[a-z]+$/.test(OYUN)) throw new Error("OYUN=<oyun kimliği>");
if (!/^\d{4}-\d{2}-\d{2}$/.test(Y)) throw new Error("Y=YYYY-AA-GG");
const uygula = process.argv[2] === "uygula";
const sql = postgres(process.env.PG_URL!, { max: 1, prepare: false });

class GeriAl extends Error {}
try {
  await sql.begin(async (tx) => {
    const [o] = await tx`select ayarlar ->> 'yayin' as yayin from ortak.oyunlar where id = ${OYUN}`;
    if (!o) throw new Error(`oyun yok: ${OYUN}`);
    console.log("şimdiki yayin".padEnd(28), o.yayin ?? "(yok = acik)");
    const once = tx`(${Y}::text::date::timestamp at time zone 'Europe/Istanbul')`;
    const say = async (ad: string, q: Promise<unknown[]>) => console.log(ad.padEnd(28), (await q).length);
    await say("skorlar", tx`delete from ortak.skorlar where oyun_id = ${OYUN} and olusturma < ${once} returning 1`);
    await say("denemeler", tx`delete from ortak.denemeler where oyun_id = ${OYUN} and olusturma < ${once} returning 1`);
    await say("kurulum_gunluk", tx`delete from ortak.kurulum_gunluk where oyun_id = ${OYUN} and olusturma < ${once} returning 1`);
    await say("lig_gruplari (+ üyeler)", tx`delete from ortak.lig_gruplari where oyun_id = ${OYUN} and olusturma < ${once} returning 1`);
    await tx`update ortak.oyunlar set ayarlar = ayarlar || '{"yayin": "acik"}'::jsonb where id = ${OYUN}`;
    console.log("yayin".padEnd(28), "acik");
    if (!uygula) throw new GeriAl();
  });
  console.log("uygulandı");
} catch (e) {
  if (!(e instanceof GeriAl)) throw e;
  console.log("kuru koşu: geri alındı");
} finally {
  await sql.end();
}
