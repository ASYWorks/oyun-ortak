#!/usr/bin/env node
// Ortak haftalık oyun raporu (kurucu 23 Kasım: Remzle'nin haftalık raporu bütün oyunlara). Salt okur, kişisel veri yok
// (yalnız sayılar). Bütün oyunların günlük kipini aynı ölçülerle karşılaştırır; oyuna özgü ayrıntı (Remzle katman/motor,
// Ense tampon vb.) oyunun kendi raporunda kalır. Testçiler (ortak.testciler) sayılmaz.
//   node scripts/haftalik-rapor.mjs [--bitis YYYY-AA-GG] [--test] [--cikti dosya.md]
// Bitiş verilmezse dün; pencere bitişten geriye 7 gün. D7 için bitişten sonraki 7 gün de okunur.
// Ölçüler (oyun başına, günlük kip, anahtar 'gunluk:<gün>'):
//   oyuncu-gün, benzersiz oyuncu, bitirme oranı (bitti / başlanan), skor sayısı, medyan puan, 100 alan oranı,
//   ilk günü bu hafta olanlarda D1 ve D7 geri dönüş.
// Alarm (yalnız en az 20 örnekte): bitirme < %50, D1 < %30, D7 < %12, medyan puan < 40 ya da > 95.
import { execSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';

const arg = process.argv.slice(2);
const deger = (b) => { const i = arg.indexOf(b); return i >= 0 ? arg[i + 1] : undefined; };
const REF = arg.includes('--test') ? 'vbygbyurswjjmiqrhvmo' : 'qzxchutjzhyzzaoxzroh';
const ORTAK = resolve(import.meta.dirname, '..');
const gunEkle = (g, n) => new Date(Date.parse(`${g}T00:00:00Z`) + n * 864e5).toISOString().slice(0, 10);
const bugun = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Istanbul' }).format(new Date());
const bitis = deger('--bitis') ?? gunEkle(bugun, -1);
if (!/^\d{4}-\d{2}-\d{2}$/.test(bitis)) throw new Error('--bitis YYYY-AA-GG');
const bas = gunEkle(bitis, -6), d7son = gunEkle(bitis, 7);
const ORNEK = 20;

const sorgu = `
with t as (select kullanici_id from ortak.testciler),
d as (
  select oyun_id as oyun, kullanici_id as k, substr(anahtar, 8)::date as gun, bitti from ortak.denemeler
   where anahtar like 'gunluk:____-__-__' and kullanici_id not in (select kullanici_id from t)
     and substr(anahtar, 8) between '${gunEkle(bas, -400)}' and '${d7son}'
),
p as (select * from d where gun between '${bas}' and '${bitis}'),
ilk as (select oyun, k, min(gun) as ilk from d group by 1, 2),
yeni as (select i.* from ilk i where i.ilk between '${bas}' and '${bitis}'),
geri as (
  select y.oyun, count(*) as n,
         count(*) filter (where exists (select 1 from d where d.oyun = y.oyun and d.k = y.k and d.gun = y.ilk + 1)) as d1,
         count(*) filter (where y.ilk + 7 <= '${d7son}'::date) as n7,
         count(*) filter (where y.ilk + 7 <= '${d7son}'::date and exists (select 1 from d where d.oyun = y.oyun and d.k = y.k and d.gun = y.ilk + 7)) as d7
    from yeni y group by 1
),
s as (
  select oyun_id as oyun, count(*) as n, percentile_cont(0.5) within group (order by puan) as medyan,
         count(*) filter (where puan >= 100) as tam
    from ortak.skorlar where tur = 'gunluk' and donem between '${bas}' and '${bitis}'
     and kullanici_id not in (select kullanici_id from t) group by 1
)
select o.id as oyun,
       (select count(*) from p where p.oyun = o.id) as oyuncu_gun,
       (select count(distinct k) from p where p.oyun = o.id) as oyuncu,
       (select count(*) filter (where bitti) from p where p.oyun = o.id) as biten,
       coalesce(s.n, 0) as skor, s.medyan, coalesce(s.tam, 0) as tam,
       coalesce(g.n, 0) as yeni, coalesce(g.d1, 0) as d1, coalesce(g.n7, 0) as n7, coalesce(g.d7, 0) as d7,
       coalesce(o.ayarlar ->> 'yayin', 'acik') as yayin
  from ortak.oyunlar o left join s on s.oyun = o.id left join geri g on g.oyun = o.id
 where o.id <> 'deneme'
 order by 2 desc, 1`;

const dosya = join(tmpdir(), `haftalik-rapor-${process.pid}.sql`);
writeFileSync(dosya, sorgu);
const cikti = execSync(`npx --prefix "${ORTAK}" supabase db query --remote=${REF} -f "${dosya}" --yes -o json`, { cwd: tmpdir(), encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
const satirlar = JSON.parse(cikti.slice(cikti.indexOf('{'))).rows ?? [];

const yuzde = (a, b) => (b ? Math.round((100 * a) / b) : null);
const goster = (v) => (v == null ? '–' : `%${v}`);
const alarmlar = [];
const out = [`# Haftalık oyun raporu: ${bas} → ${bitis}`, '', `Proje: ${REF === 'qzxchutjzhyzzaoxzroh' ? 'oyun-canli' : 'oyun-test'}. Testçiler sayılmadı. Günlük kip.`, '',
  '| Oyun | Yayın | Oyuncu-gün | Oyuncu | Bitirme | Skor | Medyan puan | 100 alan | Yeni | D1 | D7 |', '|---|---|---|---|---|---|---|---|---|---|---|'];
for (const r of satirlar) {
  const n = Number(r.oyuncu_gun), bit = yuzde(Number(r.biten), n), sk = Number(r.skor), med = r.medyan == null ? null : Math.round(Number(r.medyan));
  const d1 = yuzde(Number(r.d1), Number(r.yeni)), d7 = yuzde(Number(r.d7), Number(r.n7));
  out.push(`| ${r.oyun} | ${r.yayin} | ${n} | ${r.oyuncu} | ${goster(bit)} | ${sk} | ${med ?? '–'} | ${goster(yuzde(Number(r.tam), sk))} | ${r.yeni} | ${goster(d1)} | ${goster(d7)} |`);
  if (n >= ORNEK && bit < 50) alarmlar.push(`${r.oyun}: bitirme %${bit} (< %50)`);
  if (Number(r.yeni) >= ORNEK && d1 < 30) alarmlar.push(`${r.oyun}: D1 %${d1} (< %30)`);
  if (Number(r.n7) >= ORNEK && d7 < 12) alarmlar.push(`${r.oyun}: D7 %${d7} (< %12)`);
  if (sk >= ORNEK && med != null && (med < 40 || med > 95)) alarmlar.push(`${r.oyun}: medyan puan ${med} (${med < 40 ? 'çok zor' : 'çok kolay'} olabilir)`);
}
out.push('', '## Alarmlar', '', ...(alarmlar.length ? alarmlar.map((a) => `- ${a}`) : [`- Yok (ya da ölçüler ${ORNEK} örneğin altında).`]), '',
  '## Notlar', '', '- Önizlemedeki oyunlarda günlük yalnız testçiye açık; testçiler sayılmadığı için sayılar yayına kadar sıfıra yakın kalır.',
  '- Oyuna özgü ayrıntı oyunun kendi raporunda: Remzle `scripts/haftalik-rapor.ts` (katman, motor, kasa), Ense `npm run tampon` ve `olcum:rapor`.', '');
const md = out.join('\n');
const yol = deger('--cikti') ?? join(homedir(), '.oyun-ortak', 'rapor', `${bitis}.md`);
mkdirSync(dirname(yol), { recursive: true });
writeFileSync(yol, md);
console.log(md);
console.log(`\nyazıldı: ${yol} (${alarmlar.length} alarm)`);
