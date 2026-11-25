#!/usr/bin/env node
// Oyun yayını: temiz kopya → kilit dosyasından kurulum → (işlev oyun-test → işlev e2e) → istemci e2e (oyun-test) → canlı ortamla derleme → paket denetimi
//   → (işlev oyun-canli) → Pages → canlı doğrulama → günlük. Canlıya hiçbir şey denetimler bitmeden gitmez.
// Kullanım (oyun oturumu, kurucu onayıyla):
//   node C:/Projeler/oyunlar/_ortak/oyun-ortak/scripts/yayinla.mjs <oyun-klasoru> <commit> [--islev] [--kuru]
//   --islev : yayin.json'daki Edge Function'ları önce oyun-test'e yükler, islevE2e'yi orada koşar; canlıya paket denetiminden sonra.
//   --kuru  : derler ve denetler, hiçbir şey yüklemez (işlev de yüklenmez; islevE2e dağıtılmış test sürümüne dayandığı için atlanır).
// Çıkış: 0 yalnız canlı doğrulama geçince (kuru koşuda denetim geçince); başka her durumda 1.
// Oyun deposunda yayin.json gerekir (biçim: docs/YAYIN.md). Gizli değerler ekrana ve dosyaya yazılmaz.
// Her yayın ~/.oyun-ortak/yayin-gunlugu.jsonl dosyasına bir satır yazar; oyun-ortak oturumu son kontrolü buradan yapar.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { appendFileSync, cpSync, existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';

const ORTAK = resolve(import.meta.dirname, '..');
const PANEL = resolve(ORTAK, '../panel');
const GIZLI = join(homedir(), '.oyun-ortak');
const CANLI = 'qzxchutjzhyzzaoxzroh', TEST = 'vbygbyurswjjmiqrhvmo';
const HESAP = '892ca6bcc76288fe789a4371820362ed';

const arg = process.argv.slice(2);
const bayrak = (b) => arg.includes(b);
const [klasorArg, commit] = arg.filter((a, i) => !a.startsWith('--') && arg[i - 1] !== '--ayar');
if (!klasorArg || !commit) { console.error('kullanım: yayinla.mjs <oyun-klasoru> <commit> [--islev] [--kuru]'); process.exit(2); }
const KLASOR = resolve(klasorArg);
const kuru = bayrak('--kuru');

const gizle = (s) => String(s).replace(/eyJ[A-Za-z0-9._-]{20,}/g, '<jwt>').replace(/sb_secret_[A-Za-z0-9_-]+/g, '<gizli>');
const dur = (m) => { console.error('DURDU: ' + gizle(m)); gunluk({ sonuc: 'durdu', neden: gizle(m) }); process.exit(1); };
let temizTmp = null; // [KAYNAK, GECICI]: temiz kopya hazır olunca dolar (aşağıda)
function calis(komut, { cwd = KLASOR, env = {}, sessiz = false, izin = false, stdout = false } = {}) {
  const tmp = temizTmp && cwd === temizTmp[0] ? { TEMP: temizTmp[1], TMP: temizTmp[1], TMPDIR: temizTmp[1] } : {};
  const r = spawnSync(komut, { cwd, env: { ...process.env, ...tmp, ...env }, shell: true, encoding: 'utf8', maxBuffer: 64 << 20 });
  const cikti = (r.stdout || '') + (r.stderr || '');
  if (!sessiz) process.stdout.write(gizle(cikti.split('\n').slice(-15).join('\n')) + '\n');
  if (r.status !== 0 && !izin) {
    // Tam çıktı iş klasörüne yazılır (BG 23 Kasım: aralıklı düşmenin nedeni ekranda görünmüyordu). r.error: ENOBUFS, zaman aşımı vb.
    let yol = '';
    if (temizTmp) {
      yol = join(dirname(temizTmp[1]), 'durdu.log');
      writeFileSync(yol, gizle(`$ ${komut}\ncwd: ${cwd}\nçıkış: ${r.status} ${r.error ? r.error.message : ''}\n\n${cikti}`));
    }
    dur(`${komut.slice(0, 160)} … çıkış ${r.status}${r.error ? ` (${r.error.message})` : ''}${yol ? `\ntam çıktı: ${yol}` : ''}\n${cikti.slice(-1500)}`);
  }
  return stdout ? r.stdout || '' : cikti;
}
const envOku = (ad) => Object.fromEntries(readFileSync(join(GIZLI, ad), 'utf8').split(/\r?\n/).filter((l) => /^[A-Z_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));

const kayit = { zaman: new Date().toISOString(), klasor: KLASOR, commit, kuru, islev: bayrak('--islev') };
function gunluk(ek) { if (kuru) return; appendFileSync(join(GIZLI, 'yayin-gunlugu.jsonl'), JSON.stringify({ ...kayit, ...ek }) + '\n'); }

// 1) Ayar ve temiz kopya
const tamCommit = calis(`git rev-parse --verify "${commit}^{commit}"`, { sessiz: true, stdout: true }).trim();
kayit.commit = tamCommit.slice(0, 7); // eski kısa alan korunur
kayit.commitTam = tamCommit;
const ayarIndeks = arg.indexOf('--ayar');
// yayin.json commit'ten okunur; --ayar <dosya> yalnız ilk kurulumda (dosya henüz commit'lenmemişken) ve günlüğe yazılır.
const ayar = JSON.parse(ayarIndeks >= 0 ? readFileSync(resolve(arg[ayarIndeks + 1]), 'utf8') : calis(`git show ${tamCommit}:yayin.json`, { sessiz: true, stdout: true }));
if (ayarIndeks >= 0) kayit.ayarDosyasi = resolve(arg[ayarIndeks + 1]);
kayit.oyun = ayar.oyun;
const adres = ayar.adres ?? `https://${ayar.pages}.asyworks.com`;
const IS = join(tmpdir(), 'oyun-yayin', `${ayar.oyun}-${Date.now().toString(36)}`);
// Önceki çalışmaların klasörleri (kuru koşu ve durunca inceleme için kalır): bir günden eskiler silinir, disk sınırsız dolmasın
// (inceleme 3). Kurulum klasörün içinde; eski sürümün dışarıya bağlanan node_modules'u (junction) varsa dokunulmaz.
{
  const kok = join(tmpdir(), 'oyun-yayin');
  for (const ad of existsSync(kok) ? readdirSync(kok) : []) {
    const y = join(kok, ad), nm = join(y, 'kaynak', 'node_modules');
    try {
      if (!/^[a-z0-9-]+-[a-z0-9]+$/.test(ad) || Date.now() - statSync(y).birthtimeMs < 864e5) continue;
      if (existsSync(nm) && lstatSync(nm).isSymbolicLink()) continue;
      rmSync(y, { recursive: true, force: true });
    } catch { /* kullanımda ya da silinemedi: sonraki çalışma dener */ }
  }
}
const KAYNAK = join(IS, 'kaynak'), CIKTI = join(IS, 'cikti'), BOS = join(IS, 'bos');
mkdirSync(KAYNAK, { recursive: true }); mkdirSync(BOS);
// Her yayının kendi geçici klasörü: Metro gibi derleyiciler önbelleği %TEMP%'te tutar ve eski metni pakete koyabilir
// (Beat Greedy, 23 Kasım: silinmiş veri sorumlusu satırı önbellekten geldi). Temiz kopyadaki derleme ve e2e bunu kullanır.
const GECICI = join(IS, 'tmp'); mkdirSync(GECICI); temizTmp = [KAYNAK, GECICI];
console.log(`▸ ${ayar.oyun} ${kayit.commit} → ${IS}`);
calis(`git archive --format=tar -o "${join(IS, 'k.tar')}" ${tamCommit}`, { sessiz: true });
calis(`"${join(process.env.SystemRoot, "System32", "tar.exe")}" -xf "${join(IS, 'k.tar')}" -C "${KAYNAK}"`, { sessiz: true });
// Bağımlılıklar arşivlenmiş commit'in kilit dosyasından temiz kopyanın içine kurulur (Bulgu 6, 23 Kasım): oyun klasörünün
// node_modules'una bağlanılmaz, yerel kurulum olmasa da çalışır. Tek ve desteklenen bir kilit dosyası yoksa her şeyden önce durur.
//   package-lock.json            → npm ci
//   pnpm-lock.yaml (+ workspace) → package.json packageManager "pnpm@x.y.z" Corepack ile, --frozen-lockfile
if (ayar.baglantilar?.length) console.log(`▸ baglantilar (eski alan) yok sayıldı: ${ayar.baglantilar.join(', ')}; bağımlılıklar kurulumla gelir`);
const kilitler = ['package-lock.json', 'pnpm-lock.yaml', 'yarn.lock', 'npm-shrinkwrap.json', 'bun.lockb', 'bun.lock'].filter((k) => existsSync(join(KAYNAK, k)));
let kurulum;
if (kilitler.length !== 1) {
  dur(`kurulum: commit kökünde tek kilit dosyası olmalı, bulunan: ${kilitler.length ? kilitler.join(', ') : 'yok'}`);
} else if (kilitler[0] === 'package-lock.json') {
  kurulum = 'npm ci --no-audit --no-fund';
} else if (kilitler[0] === 'pnpm-lock.yaml') {
  const pm = JSON.parse(readFileSync(join(KAYNAK, 'package.json'), 'utf8')).packageManager ?? '';
  if (!/^pnpm@\d+\.\d+\.\d+([+-][\w.+-]*)?$/.test(pm)) dur(`kurulum: pnpm-lock.yaml var ama package.json packageManager kilitli bir pnpm sürümü değil ("${pm}")`);
  kurulum = 'corepack pnpm install --frozen-lockfile';
} else {
  dur(`kurulum: desteklenmeyen kilit dosyası ${kilitler[0]}`);
}
console.log(`▸ kurulum (${kilitler[0]}): ${kurulum}`);
calis(kurulum, { cwd: KAYNAK, env: { COREPACK_ENABLE_DOWNLOAD_PROMPT: '0', CI: '1' } });

// 2) Anahtarlar (ekrana basılmaz)
function anahtarlar(ref) {
  const j = JSON.parse(calis(`npx --prefix "${ORTAK}" supabase projects api-keys --project-ref ${ref} -o json`, { cwd: tmpdir(), sessiz: true, stdout: true }));
  return { url: `https://${ref}.supabase.co`, anon: j.find((x) => x.name === 'anon').api_key, servis: j.find((x) => x.name === 'service_role').api_key };
}
const canli = anahtarlar(CANLI), test = anahtarlar(TEST);
const istemci = envOku('oyun-canli-istemci.env');
const degisken = {
  CANLI_URL: canli.url, CANLI_ANON: canli.anon, POSTHOG_KEY: istemci.POSTHOG_KEY, TURNSTILE_SITE_KEY: istemci.TURNSTILE_SITE_KEY,
  TEST_URL: test.url, TEST_ANON: test.anon, TEST_SERVIS: test.servis, CIKTI, KAYNAK,
};
const doldur = (s) => String(s).replace(/\{([A-Z_]+)\}/g, (_, k) => { if (!(k in degisken)) dur(`yayin.json bilinmeyen yer tutucu {${k}}`); return degisken[k]; });
const ortam = (o = {}) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, doldur(v)]));
for (const k of ayar.ortamSil ?? []) delete process.env[k];

// 3) Edge Function'lar, test aşaması: oyun-test'e yükle → islevE2e. Canlı yükleme paket denetiminden sonra (adım 6b).
// Her başarılı yükleme günlük kaydına işlenir (kayit.islevYuklenen); yarıda kalan yayında hangi işlevin nereye gittiği görünür.
const islevYayini = bayrak('--islev');
if (islevYayini && !ayar.islevler?.length) dur('--islev verildi ama yayin.json islevler boş');
kayit.islevYuklenen = { test: [], canli: [] };
const islevYukle = (asama, ref) => {
  for (const fn of ayar.islevler) {
    console.log(`▸ işlev ${fn} → ${asama === 'test' ? 'oyun-test' : 'oyun-canli'}`);
    calis(`npx --prefix "${ORTAK}" supabase functions deploy ${fn} --project-ref ${ref} --workdir "${KAYNAK}" --use-api --yes`, { cwd: tmpdir() });
    kayit.islevYuklenen[asama].push(fn);
  }
};
if (islevYayini && kuru) {
  console.log(`▸ işlev (kuru): ${ayar.islevler.join(', ')} yüklenmez${ayar.islevE2e ? '; islevE2e atlandı (dağıtılmış test sürümüne dayanır)' : ''}`);
} else if (islevYayini) {
  islevYukle('test', TEST);
  if (ayar.islevE2e) { console.log('▸ işlev e2e (oyun-test)'); calis(ayar.islevE2e, { cwd: KAYNAK, env: { ...ortam(ayar.e2eOrtam), OYUN_KLASOR: KLASOR } }); }
}

// 4) İstemci e2e (oyun-test)
// OYUN_KLASOR: asıl oyun klasörü; temiz kopyada olmayan, git dışı veriyi (ör. Halka tam veri) e2e oradan okur (Halka, 25 Kasım).
if (ayar.e2e) { console.log('▸ e2e (oyun-test)'); calis(ayar.e2e, { cwd: KAYNAK, env: { ...ortam(ayar.e2eOrtam), OYUN_KLASOR: KLASOR } }); }

// 5) Canlı ortamla derleme
console.log('▸ derleme (canlı ortam)');
calis(doldur(ayar.derle), { cwd: KAYNAK, env: ortam(ayar.ortam) });
if (ayar.cikti) cpSync(join(KAYNAK, ayar.cikti), CIKTI, { recursive: true });
if (!existsSync(CIKTI)) dur('derleme çıktısı yok');

// 6) Paket denetimi
const dosyalar = [];
(function gez(d) { for (const a of readdirSync(d)) { const p = join(d, a); statSync(p).isDirectory() ? gez(p) : dosyalar.push(p); } })(CIKTI);
const yol = (p) => relative(CIKTI, p).replaceAll('\\', '/');
const metin = dosyalar.filter((p) => /\.(html|js|mjs|css|json|txt|webmanifest|svg)$|_headers$|_redirects$/.test(p)).map((p) => [yol(p), readFileSync(p, 'utf8')]);
const icerenler = (re) => metin.filter(([, t]) => re.test(t)).map(([y]) => y);
const hata = [];
if (dosyalar.some((p) => p.endsWith('.map'))) hata.push('.map dosyası var');
if (dosyalar.some((p) => yol(p).startsWith('functions/'))) hata.push('functions/ klasörü var (Pages işlevi olarak yüklenir)');
// supabaseSunucuda: istemci Supabase adresini kendi sunucusundan alır (Sticky, ST-13); canlı adres pakette aranmaz, test adresi yine yasak.
// sunucusuz: oyunun arka ucu yok (Hop Koala); canlı adres aranmaz, test adresi ve servis anahtarı yasağı sürer.
if (!ayar.supabaseSunucuda && !ayar.sunucusuz && !icerenler(new RegExp(CANLI)).length) hata.push('canlı Supabase adresi pakette yok');
if (icerenler(new RegExp(TEST)).length) hata.push('test Supabase adresi pakette: ' + icerenler(new RegExp(TEST)).slice(0, 3).join(', '));
if (icerenler(/eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]*cm9sZSI6InNlcnZpY2Vfcm9sZS/).length) hata.push('servis anahtarı pakette');
const basliklar = existsSync(join(CIKTI, '_headers')) ? readFileSync(join(CIKTI, '_headers'), 'utf8') : '';
if (!ayar.dizinlenebilir && !/noindex/i.test(basliklar)) hata.push('_headers noindex yok');
// Yerel disk yolu pakete sızmasın; wrangler node_modules adlı klasörü yüklemez (BG 23 Kasım: Metro junction yüzünden yazı tipi
// yolu "__________Projeler/.../node_modules/..." oldu, webde 4 yazı tipi HTML döndü).
const nmDosya = dosyalar.map(yol).filter((y) => /(^|\/)node_modules\//.test(y));
if (nmDosya.length) hata.push(`node_modules yolunda dosya (wrangler yüklemez): ${nmDosya.slice(0, 3).join(', ')}`);
const diskYolu = icerenler(/_{4,}Projeler[\\/]|[A-Za-z]:[\\/]{1,2}Projeler[\\/]|\/Users\/[^/"']+\/AppData\//);
if (diskYolu.length) hata.push(`yerel disk yolu pakette: ${diskYolu.slice(0, 3).join(', ')}`);
for (const desen of ayar.yasakMetin ?? []) { const v = icerenler(new RegExp(desen)); if (v.length) hata.push(`yasak metin /${desen}/: ${v.slice(0, 3).join(', ')}`); }
for (const desen of ayar.yasakDosya ?? []) { const re = new RegExp(desen); const v = dosyalar.map(yol).filter((y) => re.test(y)); if (v.length) hata.push(`yasak dosya /${desen}/: ${v.slice(0, 3).join(', ')}`); }
for (const desen of ayar.gerekliMetin ?? []) if (!icerenler(new RegExp(desen)).length) hata.push(`gerekli metin yok /${desen}/`);
// Paket özeti (yayın kanıtı): göreli yol sırasıyla her dosya için "yol\0sha256(içerik)\n" satırlarının SHA-256'sı.
// Klasör adından, zaman damgasından ve dosya sistemi sırasından bağımsızdır; aynı paket her makinede aynı özeti verir.
const ozetSatirlari = dosyalar.map((p) => [yol(p), createHash('sha256').update(readFileSync(p)).digest('hex')])
  .sort(([x], [y]) => (x < y ? -1 : x > y ? 1 : 0)).map(([y, h]) => `${y}\0${h}\n`).join('');
kayit.paket = { dosya: dosyalar.length, bayt: dosyalar.reduce((a, p) => a + statSync(p).size, 0),
  sha256: createHash('sha256').update(ozetSatirlari).digest('hex') };
console.log(`▸ denetim: ${dosyalar.length} dosya, ${hata.length ? hata.length + ' sorun' : 'temiz'}`);
if (hata.length) dur('paket denetimi:\n- ' + hata.join('\n- '));
if (kuru) { console.log(`KURU: derleme ve denetim tamam, yükleme yok. Çıktı: ${CIKTI}`); process.exit(0); }

// 6b) Edge Function'lar, canlı aşama: istemci e2e, derleme ve paket denetimi geçtikten sonra
if (islevYayini) islevYukle('canli', CANLI);

// 7) Pages (boş klasörden; başka klasörün functions/ dizini gitmesin)
console.log(`▸ Pages ${ayar.pages}`);
const yukle = calis(`npx --prefix "${PANEL}" wrangler pages deploy "${CIKTI}" --project-name ${ayar.pages} --branch main --commit-dirty=true --commit-message "${ayar.oyun} ${kayit.commit}"`, { cwd: BOS, env: { CLOUDFLARE_ACCOUNT_ID: HESAP }, sessiz: true });
kayit.pagesYayin = (yukle.match(/https:\/\/([0-9a-f]{8})\./) || [])[1] ?? null;
if (!/Deployment complete/.test(yukle)) dur('Pages yüklemesi başarısız:\n' + yukle.slice(-1200));

// 8) Canlı doğrulama: yeni index'in yerel betikleri canlı sayfada olmalı.
// Yerel betik: src/href değeri .js ile biten (sorgu dizgisi dahil, ör. app.js?v=0.4.0) ve harici olmayan adres; Vite /assets/,
// Next /_next/static/, Ezber kökteki ana-<özet>.js hepsi yakalanır. Harici betikler (https:, //, data:) sürüm kanıtı sayılmaz.
// Hiç yerel betik yoksa boş liste başarı sayılmaz: canlı HTML yereldeki index.html ile (satır sonu ve kenar boşluğu dışında) aynı olmalı.
const yerelIndex = existsSync(join(CIKTI, 'index.html')) ? readFileSync(join(CIKTI, 'index.html'), 'utf8') : '';
const harici = (u) => /^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(u);
const betikler = [...new Set([...yerelIndex.matchAll(/\b(?:src|href)\s*=\s*["']([^"']+?\.js(?:\?[^"']*)?)["']/gi)]
  .map((m) => m[1]).filter((u) => !harici(u)))];
const duz = (h) => h.replace(/\r\n/g, '\n').trim();
kayit.canliKanit = betikler.length ? { tur: 'betik', sayi: betikler.length } : { tur: 'html' };
let dogru = false;
for (let i = 0; i < 6 && !dogru; i++) {
  try {
    const r = await fetch(adres + '/', { headers: { 'cache-control': 'no-cache' } });
    const t = await r.text();
    dogru = r.ok && (betikler.length ? betikler.every((b) => t.includes(b)) : !!yerelIndex && duz(t) === duz(yerelIndex));
  } catch {}
  if (!dogru) await new Promise((s) => setTimeout(s, 5000));
}
kayit.canliDogru = dogru;
gunluk({ sonuc: dogru ? 'yayinda' : 'yayinda-dogrulanamadi', adres });
console.log(dogru ? `✔ YAYINDA: ${adres} (${ayar.oyun} ${kayit.commit}, Pages ${kayit.pagesYayin})` : `⚠ yüklendi ama ${adres} yeni sürümü göstermiyor; oyun-ortak oturumuna yaz`);
// Başarılı yayının çalışma klasörü silinir (disk dolmasın; 23 Kasım). Yalnız bu betiğin açtığı klasör: oyun-yayin altında, adı
// "<oyun>-" ile başlıyor; kurulum klasörün içinde olduğu için dışarıya bağlantı yok. Durunca ve kuru koşuda klasör inceleme için kalır.
if (dogru) {
  const kok = join(tmpdir(), 'oyun-yayin');
  const guvenli = resolve(IS).startsWith(resolve(kok) + (process.platform === 'win32' ? '\\' : '/')) && relative(kok, IS).startsWith(`${ayar.oyun}-`) && !relative(kok, IS).includes('..');
  if (guvenli) rmSync(IS, { recursive: true, force: true });
} else {
  // Yükleme yapıldı ama canlı yeni sürümü göstermiyor: başarı sayılmaz (günlükte yayinda-dogrulanamadi, işlev ve Pages kimliğiyle).
  process.exit(1);
}
