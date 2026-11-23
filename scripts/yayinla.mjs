#!/usr/bin/env node
// Oyun yayını: temiz kopya → (işlev test→canlı) → e2e (oyun-test) → canlı ortamla derleme → paket denetimi → Pages → canlı doğrulama → günlük.
// Kullanım (oyun oturumu, kurucu onayıyla):
//   node C:/Projeler/oyunlar/_ortak/oyun-ortak/scripts/yayinla.mjs <oyun-klasoru> <commit> [--islev] [--kuru]
//   --islev : yayin.json'daki Edge Function'ları önce oyun-test'e yükler, islevE2e'yi orada koşar, sonra oyun-canli'ya yükler.
//   --kuru  : derler ve denetler, hiçbir şey yüklemez.
// Oyun deposunda yayin.json gerekir (biçim: docs/YAYIN.md). Gizli değerler ekrana ve dosyaya yazılmaz.
// Her yayın ~/.oyun-ortak/yayin-gunlugu.jsonl dosyasına bir satır yazar; oyun-ortak oturumu son kontrolü buradan yapar.
import { spawnSync } from 'node:child_process';
import { appendFileSync, cpSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join, relative, resolve } from 'node:path';

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
function calis(komut, { cwd = KLASOR, env = {}, sessiz = false, izin = false, stdout = false } = {}) {
  const tmp = cwd === KAYNAK ? { TEMP: GECICI, TMP: GECICI, TMPDIR: GECICI } : {};
  const r = spawnSync(komut, { cwd, env: { ...process.env, ...tmp, ...env }, shell: true, encoding: 'utf8', maxBuffer: 64 << 20 });
  const cikti = (r.stdout || '') + (r.stderr || '');
  if (!sessiz) process.stdout.write(gizle(cikti.split('\n').slice(-15).join('\n')) + '\n');
  if (r.status !== 0 && !izin) dur(`${komut.split(' ').slice(0, 4).join(' ')} … çıkış ${r.status}\n${cikti.slice(-1500)}`);
  return stdout ? r.stdout || '' : cikti;
}
const envOku = (ad) => Object.fromEntries(readFileSync(join(GIZLI, ad), 'utf8').split(/\r?\n/).filter((l) => /^[A-Z_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));

const kayit = { zaman: new Date().toISOString(), klasor: KLASOR, commit, kuru, islev: bayrak('--islev') };
function gunluk(ek) { if (kuru) return; appendFileSync(join(GIZLI, 'yayin-gunlugu.jsonl'), JSON.stringify({ ...kayit, ...ek }) + '\n'); }

// 1) Ayar ve temiz kopya
const tamCommit = calis(`git rev-parse --verify "${commit}^{commit}"`, { sessiz: true, stdout: true }).trim();
kayit.commit = tamCommit.slice(0, 7);
const ayarIndeks = arg.indexOf('--ayar');
// yayin.json commit'ten okunur; --ayar <dosya> yalnız ilk kurulumda (dosya henüz commit'lenmemişken) ve günlüğe yazılır.
const ayar = JSON.parse(ayarIndeks >= 0 ? readFileSync(resolve(arg[ayarIndeks + 1]), 'utf8') : calis(`git show ${tamCommit}:yayin.json`, { sessiz: true, stdout: true }));
if (ayarIndeks >= 0) kayit.ayarDosyasi = resolve(arg[ayarIndeks + 1]);
kayit.oyun = ayar.oyun;
const adres = ayar.adres ?? `https://${ayar.pages}.asyworks.com`;
const IS = join(tmpdir(), 'oyun-yayin', `${ayar.oyun}-${Date.now().toString(36)}`);
const KAYNAK = join(IS, 'kaynak'), CIKTI = join(IS, 'cikti'), BOS = join(IS, 'bos');
mkdirSync(KAYNAK, { recursive: true }); mkdirSync(BOS);
// Her yayının kendi geçici klasörü: Metro gibi derleyiciler önbelleği %TEMP%'te tutar ve eski metni pakete koyabilir
// (Beat Greedy, 23 Kasım: silinmiş veri sorumlusu satırı önbellekten geldi). Temiz kopyadaki derleme ve e2e bunu kullanır.
const GECICI = join(IS, 'tmp'); mkdirSync(GECICI);
console.log(`▸ ${ayar.oyun} ${kayit.commit} → ${IS}`);
calis(`git archive --format=tar -o "${join(IS, 'k.tar')}" ${tamCommit}`, { sessiz: true });
calis(`"${join(process.env.SystemRoot, "System32", "tar.exe")}" -xf "${join(IS, 'k.tar')}" -C "${KAYNAK}"`, { sessiz: true });
if (!existsSync(join(KLASOR, 'node_modules'))) dur('oyun klasöründe node_modules yok (önce npm ci)');
process.on('exit', () => spawnSync(`cmd /c rmdir "${join(KAYNAK, 'node_modules')}"`, { shell: true })); // bağlantıyı kaldırır, hedefe dokunmaz
calis(`cmd /c mklink /J "${join(KAYNAK, 'node_modules')}" "${join(KLASOR, 'node_modules')}"`, { sessiz: true });

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

// 3) Edge Function'lar: test → islevE2e → canlı
if (bayrak('--islev')) {
  if (!ayar.islevler?.length) dur('--islev verildi ama yayin.json islevler boş');
  for (const ref of [TEST, CANLI]) {
    if (kuru && ref === CANLI) break;
    for (const fn of ayar.islevler) {
      console.log(`▸ işlev ${fn} → ${ref === TEST ? 'oyun-test' : 'oyun-canli'}`);
      calis(`npx --prefix "${ORTAK}" supabase functions deploy ${fn} --project-ref ${ref} --workdir "${KAYNAK}" --use-api --yes`, { cwd: tmpdir() });
    }
    if (ref === TEST && ayar.islevE2e) { console.log('▸ işlev e2e (oyun-test)'); calis(ayar.islevE2e, { cwd: KAYNAK, env: ortam(ayar.e2eOrtam) }); }
  }
}

// 4) İstemci e2e (oyun-test)
if (ayar.e2e) { console.log('▸ e2e (oyun-test)'); calis(ayar.e2e, { cwd: KAYNAK, env: ortam(ayar.e2eOrtam) }); }

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
if (!ayar.supabaseSunucuda && !icerenler(new RegExp(CANLI)).length) hata.push('canlı Supabase adresi pakette yok');
if (icerenler(new RegExp(TEST)).length) hata.push('test Supabase adresi pakette: ' + icerenler(new RegExp(TEST)).slice(0, 3).join(', '));
if (icerenler(/eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]*cm9sZSI6InNlcnZpY2Vfcm9sZS/).length) hata.push('servis anahtarı pakette');
const basliklar = existsSync(join(CIKTI, '_headers')) ? readFileSync(join(CIKTI, '_headers'), 'utf8') : '';
if (!ayar.dizinlenebilir && !/noindex/i.test(basliklar)) hata.push('_headers noindex yok');
for (const desen of ayar.yasakMetin ?? []) { const v = icerenler(new RegExp(desen)); if (v.length) hata.push(`yasak metin /${desen}/: ${v.slice(0, 3).join(', ')}`); }
for (const desen of ayar.yasakDosya ?? []) { const re = new RegExp(desen); const v = dosyalar.map(yol).filter((y) => re.test(y)); if (v.length) hata.push(`yasak dosya /${desen}/: ${v.slice(0, 3).join(', ')}`); }
for (const desen of ayar.gerekliMetin ?? []) if (!icerenler(new RegExp(desen)).length) hata.push(`gerekli metin yok /${desen}/`);
kayit.paket = { dosya: dosyalar.length, bayt: dosyalar.reduce((a, p) => a + statSync(p).size, 0) };
console.log(`▸ denetim: ${dosyalar.length} dosya, ${hata.length ? hata.length + ' sorun' : 'temiz'}`);
if (hata.length) dur('paket denetimi:\n- ' + hata.join('\n- '));
if (kuru) { console.log(`KURU: derleme ve denetim tamam, yükleme yok. Çıktı: ${CIKTI}`); process.exit(0); }

// 7) Pages (boş klasörden; başka klasörün functions/ dizini gitmesin)
console.log(`▸ Pages ${ayar.pages}`);
const yukle = calis(`npx --prefix "${PANEL}" wrangler pages deploy "${CIKTI}" --project-name ${ayar.pages} --branch main --commit-dirty=true --commit-message "${ayar.oyun} ${kayit.commit}"`, { cwd: BOS, env: { CLOUDFLARE_ACCOUNT_ID: HESAP }, sessiz: true });
kayit.pagesYayin = (yukle.match(/https:\/\/([0-9a-f]{8})\./) || [])[1] ?? null;
if (!/Deployment complete/.test(yukle)) dur('Pages yüklemesi başarısız:\n' + yukle.slice(-1200));

// 8) Canlı doğrulama: yeni index'in betikleri canlıda
const yerelIndex = existsSync(join(CIKTI, 'index.html')) ? readFileSync(join(CIKTI, 'index.html'), 'utf8') : '';
const betikler = [...yerelIndex.matchAll(/(?:src|href)="(\/?assets\/[^"]+\.js)"/g)].map((m) => m[1]);
let dogru = false;
for (let i = 0; i < 6 && !dogru; i++) {
  try { const r = await fetch(adres + '/', { headers: { 'cache-control': 'no-cache' } }); const t = await r.text(); dogru = r.ok && betikler.every((b) => t.includes(b)); } catch {}
  if (!dogru) await new Promise((s) => setTimeout(s, 5000));
}
kayit.canliDogru = dogru;
gunluk({ sonuc: dogru ? 'yayinda' : 'yayinda-dogrulanamadi', adres });
console.log(dogru ? `✔ YAYINDA: ${adres} (${ayar.oyun} ${kayit.commit}, Pages ${kayit.pagesYayin})` : `⚠ yüklendi ama ${adres} yeni sürümü göstermiyor; oyun-ortak oturumuna yaz`);
