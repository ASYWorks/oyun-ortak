#!/usr/bin/env node
// Onaylı gizli okuma (harness kurucu kararı 5, 28 Kasım): ~/.oyun-ortak içindeki izinli bir gizli dosyayı YALNIZ
// çalıştırılan komutun ortamına yükler; değerler hiçbir zaman ekrana çıkmaz (çıktıda geçen değer [GİZLİ] olur).
// Böylece oturum (model) gizli dosyayı kabukta açmadan e-posta, panel, veritabanı işlerini yapar.
//   node scripts/gizli-ile.mjs <ad>[,<ad>...] -- <komut> [arg...]
//   ör. node scripts/gizli-ile.mjs brevo -- node -e "fetch(...{headers:{'api-key':process.env.BREVO_API_KEY}})"
//       node scripts/gizli-ile.mjs parola -- npx supabase db query ...   (PGPASSWORD_CANLI, PGPASSWORD_TEST)
// <ad> izin listesinden: dosya adı .env'siz. "parola" = supabase-parolalar.txt ("<proje> <parola>" satırları).
import { readFileSync, existsSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

const IZINLI = ['brevo', 'resend', 'panel', 'render', 'google', 'turnstile', 'inceleme', 'giris-epostasi', 'remzle', 'odeme-webhook', 'oyun-canli-istemci', 'oyun-test-istemci', 'sahte', 'parola'];
const KLASOR = join(homedir(), '.oyun-ortak');

export function envOku(metin) {
  const out = {};
  for (const l of metin.split(/\r?\n/)) {
    const m = l.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (m) out[m[1]] = m[2].replace(/^(['"])(.*)\1$/, '$2');
  }
  return out;
}
export function parolaOku(metin) {
  const out = {};
  for (const l of metin.split(/\r?\n/)) {
    const m = l.match(/^\s*(oyun-canli|oyun-test)\s+(\S+)/);
    if (m) out[m[1] === 'oyun-canli' ? 'PGPASSWORD_CANLI' : 'PGPASSWORD_TEST'] = m[2];
  }
  return out;
}
export function maskeleyici(degerler) {
  const d = degerler.filter((v) => v && v.length >= 6).sort((a, b) => b.length - a.length);
  return (s) => d.reduce((t, v) => t.split(v).join('[GİZLİ]'), s);
}

if (import.meta.url === `file://${process.argv[1].replace(/\\/g, '/').replace(/^([A-Za-z]):/, '/$1:')}` || process.argv[1]?.endsWith('gizli-ile.mjs')) {
  const ayrac = process.argv.indexOf('--');
  const adlar = (process.argv[2] || '').split(',').filter(Boolean);
  const komut = ayrac > 0 ? process.argv.slice(ayrac + 1) : [];
  if (!adlar.length || !komut.length) { console.error('Kullanım: node scripts/gizli-ile.mjs <ad>[,<ad>] -- <komut> [arg...]'); process.exit(2); }
  const env = {};
  for (const ad of adlar) {
    if (!IZINLI.includes(ad)) { console.error(`izinli değil: ${ad} (izinliler: ${IZINLI.join(', ')})`); process.exit(2); }
    const dosya = join(KLASOR, ad === 'parola' ? 'supabase-parolalar.txt' : `${ad}.env`);
    if (!existsSync(dosya)) { console.error(`yok: ~/.oyun-ortak/${ad === 'parola' ? 'supabase-parolalar.txt' : ad + '.env'}`); process.exit(2); }
    Object.assign(env, ad === 'parola' ? parolaOku(readFileSync(dosya, 'utf8')) : envOku(readFileSync(dosya, 'utf8')));
  }
  console.error(`gizli-ile: ${adlar.join(',')} yüklendi (${Object.keys(env).join(', ')}); değerler gösterilmez.`);
  const maske = maskeleyici(Object.values(env));
  // node komutları kabuksuz (argümanlar bölünmez); npx/npm gibi .cmd'ler Windows'ta kabukla, argümanlar tırnaklı.
  const nodeMu = /^node(\.exe)?$/i.test(komut[0]);
  const tirnak = (a) => /^[\w@%+=:,./\\-]+$/.test(a) ? a : `"${a.replace(/"/g, '\\"')}"`;
  const c = nodeMu
    ? spawn(process.execPath, komut.slice(1), { env: { ...process.env, ...env }, stdio: ['inherit', 'pipe', 'pipe'] })
    : spawn(komut.map(tirnak).join(' '), { env: { ...process.env, ...env }, shell: true, stdio: ['inherit', 'pipe', 'pipe'] });
  c.stdout.on('data', (b) => process.stdout.write(maske(b.toString())));
  c.stderr.on('data', (b) => process.stderr.write(maske(b.toString())));
  c.on('close', (k) => process.exit(k ?? 1));
}
