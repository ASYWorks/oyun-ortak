#!/usr/bin/env node
// Korumalı kovaya ücretli içerik yükler (ortak çerçeve §5, ONIZLEME madde 8). Oyunun ürettiği parçalar kaynak klasördedir;
// her dosya `korumali/<onek>/<dosya>` yoluna yazılır (x-upsert), sonra geri indirilip sha256 denetlenir.
//   SUPABASE_URL=https://<ref>.supabase.co SERVIS=<servis anahtarı> node scripts/korumali-yukle.mjs <kaynak> <onek> [--kuru]
//   Örnek: ... node scripts/korumali-yukle.mjs C:/Projeler/oyunlar/sifre-burosu/korumali-cikti/bolum remzle/paket_tam/bolum
// Kaynakta surum.json varsa ({"<dosya>": "<sha256>"} ya da {dosyalar: {...}}) indirilen her dosya ona göre de denetlenir.
// Servis anahtarı ekrana yazılmaz.
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const [kaynak, onek] = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const kuru = process.argv.includes('--kuru');
const URL_ = process.env.SUPABASE_URL, KEY = process.env.SERVIS;
if (!kaynak || !onek || !/^[a-z]+\/[a-z0-9_]+(\/[a-z0-9_-]+)*$/.test(onek)) throw new Error('kullanım: korumali-yukle.mjs <kaynak> <oyun/hak[/alt]> [--kuru]');
if (!kuru && (!URL_ || !KEY)) throw new Error('SUPABASE_URL ve SERVIS gerekli');

const sha = (b) => createHash('sha256').update(b).digest('hex');
const dosyalar = readdirSync(kaynak).filter((d) => d.endsWith('.json')).sort();
let beklenen = {};
try { const s = JSON.parse(readFileSync(join(kaynak, 'surum.json'), 'utf8')); beklenen = s.dosyalar ?? s.parcalar ?? s; } catch { /* surum.json yok */ }
// surum.json anahtarı dosya adı ya da onunla biten yol (ör. 'bolum/morse-1.json'); değer özet ya da {sha256}.
const beklenenOzet = (d) => { const k = Object.keys(beklenen).find((x) => x === d || x.endsWith('/' + d)); const v = k && beklenen[k]; return typeof v === 'string' ? v : v?.sha256; };
const toplam = dosyalar.reduce((a, d) => a + readFileSync(join(kaynak, d)).length, 0);
console.log(`${dosyalar.length} dosya, ${(toplam / 1048576).toFixed(1)} MB → korumali/${onek}/`);
if (kuru) { console.log('KURU: yükleme yok.'); process.exit(0); }

const h = { apikey: KEY, Authorization: `Bearer ${KEY}` };
let yuklenen = 0, hatali = [];
for (const d of dosyalar) {
  const veri = readFileSync(join(kaynak, d));
  const yol = `${onek}/${d}`;
  let r;
  for (let deneme = 0; deneme < 3; deneme++) {
    r = await fetch(`${URL_}/storage/v1/object/korumali/${yol}`, { method: 'POST', headers: { ...h, 'Content-Type': 'application/json', 'x-upsert': 'true' }, body: veri });
    if (r.ok) break;
    await new Promise((s) => setTimeout(s, 1000 * (deneme + 1)));
  }
  if (!r.ok) { hatali.push(`${d}: yükleme ${r.status} ${(await r.text()).slice(0, 120)}`); continue; }
  const geri = Buffer.from(await (await fetch(`${URL_}/storage/v1/object/korumali/${yol}`, { headers: h })).arrayBuffer());
  const ozet = sha(geri);
  if (ozet !== sha(veri)) hatali.push(`${d}: indirilen yerelden farklı`);
  else if (d !== 'surum.json' && beklenenOzet(d) && beklenenOzet(d) !== ozet) hatali.push(`${d}: surum.json özetiyle uyuşmuyor`);
  else yuklenen++;
}
console.log(`yüklenen ve doğrulanan: ${yuklenen}/${dosyalar.length}`);
if (hatali.length) { console.log('SORUNLU:\n- ' + hatali.join('\n- ')); process.exit(1); }
