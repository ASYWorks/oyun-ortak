#!/usr/bin/env node
// Ortak yapıya geçiş denetimi (kurucu 23 Kasım: "hepsinin ortak yapıya geçtiğinden emin ol"). Her oyunun deposundan ve
// canlı ayardan kanıt toplar; tablo basar. Pazar listesinde (PERIYODIK 8f) koşulur.
//   node scripts/ortak-yapi-denetim.mjs            → depo kanıtları
//   node scripts/ortak-yapi-denetim.mjs --canli    → canlıdaki ayarlar.yayin ve yayin_tarihi de
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const KOK = 'C:/Projeler/oyunlar';
const ORTAK = join(KOK, '_ortak/oyun-ortak');
const OYUNLAR = [
  ['halka-kelime', 'halka'], ['sezgi', 'sezgi'], ['sticky-ten', 'sticky'], ['minik-oyun-kutusu', null],
  ['ense-nasil-olsun', 'ense'], ['sahte-masasi', 'sahte'], ['sifre-burosu', 'remzle'], ['ezber-bozan', 'ezber'],
  ['koz-hesabi', 'koz'], ['kapi-ustasi', 'kapi'], ['mahalle-donusumu', 'mahalle'], ['ifade-kati', 'ifade'],
];
const ISTISNA_ONIZLEME = new Set(['minik-oyun-kutusu']);
const GEREKLI_PAKET = '0.22';
// Bayrakları kendi sunucusundan alan oyun (Sticky: Render sunucusu etkin_bayraklar sorar) paket sürümüne bağlı değil.
const PAKET_GEREKMEZ = new Set(['sticky-ten']);
// Oyunda olmayan özellik: Sticky'de günlük takvim ve ücretli seviye yok.
const UYGULANMAZ = { 'sticky-ten': new Set(['tarih', 'korumali']) };

const git = (dir, args) => spawnSync('git', args, { cwd: dir, encoding: 'utf8' }).stdout?.trim() ?? '';
const oku = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
function tumDosyalar(dir, uz, sinir = 4000) {
  const out = [];
  const gez = (d) => { if (out.length > sinir) return; for (const a of readdirSync(d, { withFileTypes: true })) {
    if (['node_modules', '.git', 'dist', '_ek', '.cache'].includes(a.name)) continue;
    const p = join(d, a.name); a.isDirectory() ? gez(p) : uz.test(a.name) && out.push(p); } };
  if (existsSync(dir)) gez(dir);
  return out;
}
const iceren = (dir, uz, re) => tumDosyalar(dir, uz).some((p) => re.test(oku(p)));

let canli = {};
if (process.argv.includes('--canli')) {
  const sorgu = join(tmpdir(), 'ortak-yapi-denetim.sql');
  require_fs_write(sorgu, "select id, ayarlar->>'yayin' as yayin, ayarlar->>'yayin_tarihi' as tarih from ortak.oyunlar;");
  const r = spawnSync('npx', ['--prefix', ORTAK, 'supabase', 'db', 'query', '--remote=qzxchutjzhyzzaoxzroh', '-f', sorgu, '--yes', '-o', 'json'], { cwd: tmpdir(), encoding: 'utf8', shell: process.platform === 'win32' });
  try { const j = JSON.parse(r.stdout); for (const s of (j.rows ?? j)) canli[s.id] = s; } catch { console.error('canlı okunamadı'); }
}
function require_fs_write(p, t) { spawnSync(process.execPath, ['-e', `require('fs').writeFileSync(${JSON.stringify(p)}, ${JSON.stringify(t)})`]); }

const satirlar = [];
for (const [klasor, id] of OYUNLAR) {
  const d = join(KOK, klasor);
  if (!existsSync(d)) { satirlar.push({ oyun: klasor, not: 'klasör yok' }); continue; }
  const pkgYol = ['package.json', 'apps/mobile/package.json', 'app/package.json'].map((p) => join(d, p)).find((p) => oku(p).includes('@oyun/ortak')) ?? join(d, 'package.json');
  const pkg = JSON.parse(oku(pkgYol) || '{}');
  const surum = (pkg.dependencies?.['@oyun/ortak'] ?? pkg.devDependencies?.['@oyun/ortak'] ?? '').match(/v?(\d+\.\d+\.\d+)/)?.[1] ?? '-';
  const remote = git(d, ['remote', 'get-url', 'origin']);
  const yayinJson = existsSync(join(d, 'yayin.json'));
  const yj = yayinJson ? JSON.parse(oku(join(d, 'yayin.json'))) : {};
  const fnDir = join(d, 'supabase/functions');
  const ozellik = iceren(fnDir, /\.ts$/, /ozellikAcik|etkin_bayraklar/) || iceren(join(d, 'server'), /\.(ts|js)$/, /etkin_bayraklar/) || iceren(join(d, 'supabase'), /\.sql$/, /etkin_bayraklar/)
    || (id !== null && tumDosyalar(join(ORTAK, 'supabase/migrations'), /\.sql$/).some((p) => oku(p).includes(`etkin_bayraklar('${id}'`)));
  const src = ['src', 'app', 'apps', 'client', 'web'].map((s) => join(d, s));
  const onizleme = src.some((s) => iceren(s, /\.(ts|tsx|js|svelte|vue)$/, /onizleme/));
  const testci = src.some((s) => iceren(s, /\.(ts|tsx|js|svelte|vue)$/, /testci/));
  const misafirBayrak = src.some((s) => iceren(s, /\.(ts|tsx|js|svelte|vue)$/, /oyunBayraklari/)) || (PAKET_GEREKMEZ.has(klasor) && onizleme);
  const yayinTarihi = src.some((s) => iceren(s, /\.(ts|tsx|js|svelte|vue)$/, /yayin_tarihi/));
  const docs = tumDosyalar(join(d, 'docs'), /\.md$/).map(oku).join('\n') + oku(join(d, 'CLAUDE.md'));
  const yayinGunu = /yayin-temizligi|yayın günü/i.test(docs);
  // Ücretli içerik ya korumali kovasından ya da hak denetimli sunucu işleminden (Ezber: dogrula-ezber "icerik") iner.
  const korumali = /korumali|korumalı/i.test(docs) || !!iceren(fnDir, /\.ts$/, /hakki_var|islem === "icerik"/);
  const c = id ? canli[id] : undefined;
  const istisna = ISTISNA_ONIZLEME.has(klasor);
  satirlar.push({
    oyun: klasor,
    depo: /github\.com\/ASYWorks\//.test(remote) ? '✓' : '✗',
    paket: istisna ? '–' : (surum.startsWith(GEREKLI_PAKET) || PAKET_GEREKMEZ.has(klasor) ? surum : `✗ ${surum}`),
    yayin_json: istisna && !yayinJson ? '– (sunucusuz)' : yayinJson ? ((yj.yasakMetin?.length || yj.yasakDosya?.length) ? '✓' : '✓ desen yok') : '✗',
    sunucu: istisna ? '–' : (ozellik ? '✓' : '✗'),
    onizleme: istisna ? 'istisna' : (onizleme && testci ? '✓' : '✗'),
    misafir: istisna ? '–' : (misafirBayrak ? '✓' : '✗'),
    tarih: istisna || UYGULANMAZ[klasor]?.has('tarih') ? '–' : (yayinTarihi ? '✓' : '✗'),
    yayin_gunu: istisna ? '–' : (yayinGunu ? '✓' : '✗'),
    korumali: istisna || UYGULANMAZ[klasor]?.has('korumali') ? '–' : (korumali ? '✓' : '✗'),
    canli: c ? `${c.yayin ?? 'acik'}${c.tarih ? ' ' + c.tarih : ''}` : (Object.keys(canli).length ? '-' : ''),
  });
}
console.table(satirlar);
const eksik = satirlar.filter((s) => Object.values(s).some((v) => String(v).startsWith('✗')));
console.log(eksik.length ? `Eksiği olan: ${eksik.map((s) => s.oyun).join(', ')}` : 'Hepsi tamam.');
