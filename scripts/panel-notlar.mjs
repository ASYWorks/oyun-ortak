#!/usr/bin/env node
// Panel notları (göç 8400): kurucunun panel.asyworks.com'da oyun oyun girdiği test notlarını okur ve durumunu değiştirir.
// Servis anahtarı `supabase projects api-keys` ile alınır, ekrana yazılmaz. Varsayılan proje canlı (panel canlıya yazar).
//   node scripts/panel-notlar.mjs                      yeni notlar, oyun oyun (iletilecek metin)
//   node scripts/panel-notlar.mjs --hepsi              son 300 not, durumlarıyla
//   node scripts/panel-notlar.mjs --gonderildi 12,13   iletilen notları işaretler
//   node scripts/panel-notlar.mjs --yapildi 12 "sonuç" oturum düzeltince işaretler (sonuç isteğe bağlı, ≤1000)
//   --test                                             oyun-test projesinde çalışır
import { execSync } from 'node:child_process';
import { resolve } from 'node:path';

const arg = process.argv.slice(2);
const deger = (b) => { const i = arg.indexOf(b); return i >= 0 ? arg[i + 1] : undefined; };
const REF = arg.includes('--test') ? 'vbygbyurswjjmiqrhvmo' : 'qzxchutjzhyzzaoxzroh';
const ORTAK = resolve(import.meta.dirname, '..');

const anahtarlar = JSON.parse(execSync(`npx --prefix "${ORTAK}" supabase projects api-keys --project-ref ${REF} -o json`, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }));
const KEY = anahtarlar.find((k) => k.name === 'service_role')?.api_key;
if (!KEY) throw new Error('servis anahtarı alınamadı');
const URL_ = `https://${REF}.supabase.co/rest/v1/panel_notlar`;
const h = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Accept-Profile': 'ortak', 'Content-Profile': 'ortak', 'Content-Type': 'application/json' };

async function istek(yol, secenek = {}) {
  const r = await fetch(URL_ + yol, { ...secenek, headers: { ...h, ...(secenek.headers ?? {}) } });
  if (!r.ok) throw new Error(`${r.status} ${(await r.text()).slice(0, 300)}`);
  return r.status === 204 ? null : r.json();
}
const idler = (s) => { const v = String(s ?? '').split(',').map(Number); if (!v.length || v.some((x) => !Number.isInteger(x) || x <= 0)) throw new Error('id listesi: 12,13'); return v; };

if (deger('--gonderildi')) {
  const v = idler(deger('--gonderildi'));
  const r = await istek(`?id=in.(${v.join(',')})&durum=eq.yeni`, { method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify({ durum: 'gonderildi', gonderildi: new Date().toISOString() }) });
  console.log(`gönderildi işaretlenen: ${r.length}/${v.length}`);
} else if (deger('--yapildi')) {
  const [id] = idler(deger('--yapildi'));
  const i = arg.indexOf('--yapildi'); const sonuc = arg[i + 2] && !arg[i + 2].startsWith('--') ? arg[i + 2].slice(0, 1000) : null;
  const r = await istek(`?id=eq.${id}`, { method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify({ durum: 'yapildi', sonuc }) });
  console.log(r.length ? `yapıldı: ${id}` : `not yok: ${id}`);
} else {
  const hepsi = arg.includes('--hepsi');
  const notlar = await istek(`?select=id,oyun,metin,durum,olusturma,sonuc&order=oyun.asc,olusturma.asc&limit=300${hepsi ? '' : '&durum=eq.yeni'}`);
  if (!notlar.length) console.log(hepsi ? 'not yok' : 'yeni not yok');
  const gruplar = Object.groupBy(notlar, (n) => n.oyun);
  // Paneldeki kimlik → yerel klasör (oturum.ps1 adı). Eşleşmeyenler aynı ad. genel: bu oturum (oyun-ortak).
  const KLASOR = { 'beat-greedy': 'sezgi', remzle: 'sifre-burosu', genel: 'oyun-ortak (bu oturum)' };
  for (const [oyun, ns] of Object.entries(gruplar)) {
    console.log(`\n## ${oyun} → ${KLASOR[oyun] ?? oyun} (${ns.length})`);
    for (const n of ns) console.log(`- [${n.id}${hepsi ? ' ' + n.durum : ''}] ${n.olusturma.slice(0, 16).replace('T', ' ')}: ${n.metin.replace(/\s+/g, ' ')}${n.sonuc ? `  → ${n.sonuc}` : ''}`);
  }
}
