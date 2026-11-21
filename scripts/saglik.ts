// Sağlık denetimi (20 Kasım işletim incelemesi): ortak.isletim_durumu()'nu okur, eşiklere göre uyarı ve müdahale adımı yazar.
// Kullanım: node scripts/saglik.ts [canli|test]   (salt okunur; Supabase CLI girişi gerekir)
// Çıkış kodu: 0 sorun yok, 1 uyarı var, 2 denetim yapılamadı (bu da bir uyarıdır: izleme çalışmıyor demektir).
// Eşikler ve müdahaleler docs/ISLETIM.md §6 ile aynı.
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const REF = { canli: "qzxchutjzhyzzaoxzroh", test: "vbygbyurswjjmiqrhvmo" }[process.argv[2] ?? "canli"];
if (!REF) throw new Error("kullanım: node scripts/saglik.ts canli|test");

type Is = { ad: string; etkin: boolean; gecikti: boolean; basarisiz_24s: number; son_hata: string | null; son_basari: string | null };
type Durum = {
  bugun: string;
  isler: Is[];
  icerik: { halka_gunluk_kalan_gun: number | null; halka_bugun_var: boolean; halka_turnuva_son_bitis: string | null; sezgi_gunluk_son: string | null };
  bekleyen: { kapanmamis_gecmis_lig_grubu: number; odulsuz_turnuva: number };
  son_24s: Record<string, number>;
  boyut: { veritabani_mb: number; hiz_sinirlari_satir: number };
};

let d: Durum;
try {
  const dizin = mkdtempSync(join(tmpdir(), "saglik-"));
  const dosya = join(dizin, "s.sql");
  writeFileSync(dosya, "select ortak.isletim_durumu() as v;");
  // Depodaki sabit sürüm (package.json'daki supabase) doğrudan Node ile, kabuksuz; npx ağdan sürüm çekmesin.
  // cwd yapılandırmasız geçici klasör: config.toml'daki env(...) gizli değerleri gerekmesin.
  const cli = fileURLToPath(new URL("../node_modules/supabase/dist/supabase.js", import.meta.url));
  const cikti = execFileSync(process.execPath, [cli, "db", "query", `--remote=${REF}`, "-f", dosya, "--read-only", "--yes", "-o", "json"], { encoding: "utf8", cwd: dizin, stdio: ["ignore", "pipe", "pipe"] });
  if (!cikti.includes("{")) throw new Error(`CLI çıktısı boş: ${cikti.trim().slice(-300)}`);
  // CLI çıktısı: ajan ortamında {rows:[...]}, zamanlanmış görevde düz dizi (20 Kasım). İkisi de okunur.
  const j = JSON.parse(cikti.slice(cikti.search(/^[[{]/m)));
  d = (Array.isArray(j) ? j : j.rows)[0].v as Durum;
} catch (e) {
  console.log(`DENETİM YAPILAMADI: ${String((e as { stderr?: string }).stderr || (e as Error).message).trim().slice(-300)}\nMüdahale: Supabase CLI girişini ve projenin ayakta olduğunu kontrol et (ücretsiz planda 7 gün hareketsiz proje duraklar).`);
  process.exit(2);
}

const uyari: string[] = [];
const ekle = (m: string, mud: string) => uyari.push(`• ${m}\n  Müdahale: ${mud}`);
const gunFarki = (a: string, b: string) => Math.round((Date.parse(a) - Date.parse(b)) / 864e5);
const pazartesiSabah = (() => { const s = new Date(Date.now() + 3 * 3600e3); return s.getUTCDay() === 1 && s.getUTCHours() < 5; })();

for (const i of d.isler) {
  if (!i.etkin) ekle(`Zamanlanmış iş kapalı: ${i.ad}`, "Bilerek kapatılmadıysa: select cron.alter_job(jobid, active := true) ...");
  else if (i.basarisiz_24s > 0) ekle(`${i.ad} son 24 saatte ${i.basarisiz_24s} kez başarısız: ${i.son_hata ?? ""}`, "Hatayı oku; iş tekrarlanabilir (ödül ve kapanış işleri çift etki üretmez), düzeltince elle bir kez çalıştır.");
  else if (i.gecikti) ekle(`${i.ad} zamanında başarıyla çalışmadı (son başarı ${i.son_basari ?? "yok"})`, "cron.job_run_details'e bak; elle çalıştırmak güvenli (lig_kapat ve turnuva_odul_ver geride kalanları telafi eder).");
}
const k = d.icerik;
if (!k.halka_bugun_var) ekle("Halka'da bugünün bulmacası YOK", "Hemen Halka oturumu upload_daily.ts çalıştırsın (önce test, sonra canlı). Oyuncular bugünü açamıyor.");
else if ((k.halka_gunluk_kalan_gun ?? 0) < 14) ekle(`Halka'da yalnız ${k.halka_gunluk_kalan_gun} günlük bulmaca kaldı`, "Halka oturumu yeni günleri üretip yüklesin (hedef: en az 30 gün ileri).");
if (k.halka_turnuva_son_bitis && gunFarki(k.halka_turnuva_son_bitis, d.bugun) < 7) ekle(`Halka'da gelecek hafta sonu turnuvası yok (son bitiş ${k.halka_turnuva_son_bitis})`, "Halka oturumu turnuva bulmacalarını yüklesin.");
if (k.sezgi_gunluk_son && gunFarki(k.sezgi_gunluk_son, d.bugun) < 7) ekle(`Beat Greedy'de ${gunFarki(k.sezgi_gunluk_son, d.bugun)} günlük bulmaca kaldı`, "Beat Greedy oturumu günlük bulmacaları üretsin.");
if (d.bekleyen.kapanmamis_gecmis_lig_grubu > 0 && !pazartesiSabah) ekle(`${d.bekleyen.kapanmamis_gecmis_lig_grubu} geçmiş hafta lig grubu kapanmamış`, "select ortak.lig_kapat(); (tekrar çağrılması zararsız)");
if (d.bekleyen.odulsuz_turnuva > 0) ekle(`${d.bekleyen.odulsuz_turnuva} biten turnuvanın Şampiyon ödülü verilmemiş`, "select halka.turnuva_odul_ver(); (çift ödül üretmez)");
if (d.boyut.veritabani_mb > 400) ekle(`Veritabanı ${d.boyut.veritabani_mb} MB (ücretsiz sınır 500 MB)`, "docs/ISLETIM.md §7 saklama politikasını uygula ya da Pro'ya geç.");

console.log(`Sağlık ${process.argv[2] ?? "canli"} — ${d.bugun}; son 24 saat: ${Object.entries(d.son_24s).map(([a, b]) => `${a} ${b}`).join(", ")}; veritabanı ${d.boyut.veritabani_mb} MB`);
console.log(uyari.length ? `${uyari.length} UYARI\n${uyari.join("\n")}` : "Sorun yok.");
process.exit(uyari.length ? 1 : 0);
