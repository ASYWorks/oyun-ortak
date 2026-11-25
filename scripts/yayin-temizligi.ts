// Yayın günü: önizlemeden çıkış (göç 8280, kurucu 22 Kasım). Önizlemede günlük, lig ve etkinlik yalnız testçilere açıktı.
// Yayın gününden (Y, İstanbul 00:00) önce TESTÇİLERİN oluşturduğu ortak skor, deneme, kurulum ve lig üyeliği satırları silinir.
// Üyesi kalmayan lig grubu da silinir. ayarlar.yayin 'acik' olur.
//   PG_URL=... OYUN=koz Y=2027-01-15 node scripts/yayin-temizligi.ts          → kuru: sayar, geri alır
//   PG_URL=... OYUN=koz Y=2027-01-15 node scripts/yayin-temizligi.ts uygula   → uygular (canlıda kurucu onayıyla)
// Güvenlik (Codex hata bulgusu 3, 25 Kasım):
// - Oyun önizlemede değilse durur; ikinci çalıştırma hiçbir şey silmez.
// - ayarlar.yayin_tarihi varsa ve Y'den farklıysa durur.
// - Normal oyuncunun satırına dokunulmaz (oyun önceden açık oynanmışsa da).
// Dokunulmayanlar: oyuncular (adlar), haklar ve ödemeler, ödüller, bulut kayıtları, oyunun kendi şeması.
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
    const [o] = await tx`select ayarlar ->> 'yayin' as yayin, ayarlar ->> 'yayin_tarihi' as tarih from ortak.oyunlar where id = ${OYUN} for update`;
    if (!o) throw new Error(`oyun yok: ${OYUN}`);
    console.log("şimdiki yayin".padEnd(28), o.yayin ?? "(yok = acik)", "yayin_tarihi", o.tarih ?? "(yok)");
    if (o.yayin !== "onizleme") throw new Error(`oyun onizleme değil (${o.yayin ?? "acik"}); temizlik yapılmaz`);
    if (o.tarih && o.tarih !== Y) throw new Error(`yayin_tarihi (${o.tarih}) Y (${Y}) ile aynı değil; temizlik yapılmaz`);
    const once = tx`(${Y}::text::date::timestamp at time zone 'Europe/Istanbul')`;
    const testci = tx`(select kullanici_id from ortak.testciler)`;
    const say = async (ad: string, q: Promise<unknown[]>) => console.log(ad.padEnd(28), (await q).length);
    await say("skorlar (testçi)", tx`delete from ortak.skorlar where oyun_id = ${OYUN} and olusturma < ${once} and kullanici_id in ${testci} returning 1`);
    await say("denemeler (testçi)", tx`delete from ortak.denemeler where oyun_id = ${OYUN} and olusturma < ${once} and kullanici_id in ${testci} returning 1`);
    await say("kurulum_gunluk (testçi)", tx`delete from ortak.kurulum_gunluk where oyun_id = ${OYUN} and olusturma < ${once} and kullanici_id in ${testci} returning 1`);
    await say("lig_uyeleri (testçi)", tx`delete from ortak.lig_uyeleri u using ortak.lig_gruplari g where u.grup_id = g.id and g.oyun_id = ${OYUN} and g.olusturma < ${once} and u.kullanici_id in ${testci} returning 1`);
    await say("boş lig_gruplari", tx`delete from ortak.lig_gruplari g where g.oyun_id = ${OYUN} and g.olusturma < ${once} and not exists (select 1 from ortak.lig_uyeleri u where u.grup_id = g.id) returning 1`);
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
