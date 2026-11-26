// Salt okuma hız ölçümü (HIZ_PLANI madde 13): node hiz-olc.mjs <site> [tekrar] [gecis]
// Soğuk (yeni bağlam) + sıcak (aynı bağlamda ikinci açılış) + geçişler; Yavaş 4G (150 ms, 1,6/0,75 Mbps) + CPU 4x.
// Ortam: PLAYWRIGHT_MODULE (isteğe bağlı mutlak yol / file: URL), CHROME (isteğe bağlı tarayıcı yolu),
//        HIZ_TEST_URL (isteğe bağlı, yalnız loopback; bu kipte dış bağlantılar kesilir).
import { SITES, playwrightYukle, yerelAdres, loopbackMi } from './siteler.mjs';
import { writeFileSync } from 'node:fs';

const YARDIM = `kullanım: node hiz-olc.mjs <site> [tekrar 1–10, varsayılan 3] [gecis]
siteler: ${Object.keys(SITES).join(', ')}
ortam: PLAYWRIGHT_MODULE=<mutlak yol|file: URL>  CHROME=<tarayıcı yolu>  HIZ_TEST_URL=<loopback adres>`;
const argv = process.argv.slice(2);
if (!argv.length || argv.includes('--help') || argv.includes('-h')) { console.log(YARDIM); process.exit(argv.length ? 0 : 2); }

// Raporlarda adresin sorgu ve parça kısmı tutulmaz (oturum ya da giriş belirteci sızmasın).
const temizAdres = (adres) => {
  if (typeof adres !== 'string') return adres;
  if (adres.startsWith('data:')) return 'data:';
  try { const u = new URL(adres); u.search = ''; u.hash = ''; u.username = ''; u.password = ''; return u.href; } catch { return adres.split(/[?#]/)[0]; }
};
// Dışa yazılan hata dizelerinde geçen mutlak http(s) adresleri de aynı temizleyiciden geçer (goto zaman aşımı, net::ERR_...).
const temizHata = (metin) => (metin == null ? metin : String(metin).replace(/https?:\/\/[^\s"'<>)\]]+/g, (a) => temizAdres(a)));

// hazır: görünür olunca "ilk etkileşime hazır" sayılan öğe; gec: zararsız geçiş düğmeleri
const SPEC = {
  halka: { hazir: ['#baslaBtn', ''], gec: [['seviye listesi', '#openList', ''], ['menü', '#openInfo', '']] },
  beatgreedy: { hazir: ['button', 'Kestirme'], gec: [['oyun listesi sonraki sayfa', 'role:button', 'Sonraki sayfa'], ['profil', 'a', '^Profil$']] },
  sticky: { hazir: ['button', 'Misafir olarak devam et'], gec: [['gizlilik', 'role:link', 'Gizlilik|Privacy'], ['dil EN', 'button.lang', '^EN$']] },
  ense: { hazir: ['a', 'Dükkânı aç'], gec: [['bölümler', 'a.fayans', '^Bölümler$'], ['ayarlar', 'a.fayans', '^Ayarlar$']] },
  sahte: { hazir: ['button', '^Bölümler$'], gec: [['bölümler', 'button', '^Bölümler$'], ['menü', 'button.menu-btn', '']] },
  remzle: { hazir: ['a.btn.primary', 'Devam et'], gec: [['aile filtresi', 'button.aile', ''], ['hesap', 'role:link', 'Hesap']] },
  ezber: { hazir: ['a.dugme.ana', 'Başla'], gec: [['sınıflar', 'a.dugme', '^Sınıflar$'], ['ayarlar', 'a.dugme', '^Ayarlar$'], ['kurallar', '#kurallar', '']] },
  koz: { hazir: ['button', '.'], gec: [['öğretici sonraki', 'button.birincil', 'Sonraki'], ['öğreticiyi geç (Batak biliyorum)', 'button', 'Batak biliyorum']] },
  kapi: { hazir: ['button', 'Öğreticiye başla|Oyna'], gec: [['seviye haritası', 'button.kisayol', 'Seviye haritası'], ['defter', 'button', '^Defter$']] },
  mahalle: { hazir: ['button.dugme.ana', 'Başla'], gec: [['ayarlar', 'button.gez', '^Ayarlar$'], ['mahalle', 'button.gez', '^Mahalle$']] },
  ifade: { hazir: ['button', 'Başla|Start'], gec: [['dil English', 'role:button', '^English$'], ['başla (öğretici girişi)', 'button.dugme.ana', 'Başla|Start']] },
  hopkoala: { hazir: ['button', 'Hop Koala'], gec: [['resimli kitaplar', 'role:button', 'Resimli Kitaplar'], ['basit oyunlar', 'role:button', 'Basit Oyunlar']] },
  elbitir: { hazir: ['button', 'Biliyorum|Geç'], gec: [['öğreticiyi geç', 'button', '^Geç$'], ['ayarlar', 'a', '^Ayarlar$']] },
};

const site = argv[0];
if (!Object.hasOwn(SITES, site) || !Object.hasOwn(SPEC, site)) { console.error(`bilinmeyen site: ${site}\n${YARDIM}`); process.exit(2); }
const nArg = argv[1] ?? '3';
if (!/^\d+$/.test(nArg) || +nArg < 1 || +nArg > 10) { console.error(`tekrar 1–10 arası tam sayı olmalı: ${nArg}`); process.exit(2); }
const N = +nArg;
if (argv[2] !== undefined && argv[2] !== 'gecis') { console.error(`bilinmeyen kip: ${argv[2]} (yalnız "gecis")`); process.exit(2); }
const GONLY = argv[2] === 'gecis';
let URL0, YEREL = false;
try { if (process.env.HIZ_TEST_URL) { URL0 = yerelAdres(process.env.HIZ_TEST_URL); YEREL = true; } else URL0 = SITES[site]; }
catch (e) { console.error(e.message); process.exit(2); }
const spec = SPEC[site];
const { chromium } = await playwrightYukle().catch((e) => { console.error(e.message); process.exit(2); });

// Sayfa içi gözlemciler (her belge açılışında yeniden kurulur)
const INIT = ([sel, txt]) => {
  const M = (window.__m = { lcp: [], ls: [], lt: [], loaf: [], ev: [], hazir: null, fcp: null, gecis: null });
  const po = (type, f, o = {}) => { try { new PerformanceObserver(l => l.getEntries().forEach(f)).observe({ type, buffered: true, ...o }); } catch {} };
  po('paint', e => { if (e.name === 'first-contentful-paint') M.fcp = e.startTime; });
  po('largest-contentful-paint', e => M.lcp.push({ t: e.startTime, size: e.size, el: e.element ? e.element.tagName + (e.element.id ? '#' + e.element.id : '') + (typeof e.element.className === 'string' && e.element.className ? '.' + e.element.className.split(' ')[0] : '') : null, url: e.url || null }));
  po('layout-shift', e => { if (!e.hadRecentInput) M.ls.push({ t: e.startTime, v: e.value }); });
  po('longtask', e => M.lt.push({ t: e.startTime, d: e.duration }));
  po('long-animation-frame', e => M.loaf.push({ t: e.startTime, d: e.duration, block: e.blockingDuration, scripts: (e.scripts || []).sort((a, b) => b.duration - a.duration).slice(0, 3).map(s => ({ d: Math.round(s.duration), src: (s.sourceURL || '').slice(-80), fn: s.sourceFunctionName, inv: (s.invoker || '').slice(0, 60) })) }));
  po('event', e => M.ev.push({ name: e.name, t: e.startTime, d: e.duration, proc: e.processingEnd - e.processingStart }), { durationThreshold: 16 });
  const re = new RegExp(txt || '');
  const gorunur = e => { const r = e.getBoundingClientRect(); if (r.width < 4 || r.height < 4 || r.top >= innerHeight || r.bottom <= 0) return false; const s = getComputedStyle(e); return s.visibility !== 'hidden' && s.display !== 'none' && +s.opacity > 0.1; };
  const bak = () => { if (M.hazir != null) return; try { for (const e of document.querySelectorAll(sel)) if (re.test((e.innerText || e.getAttribute('aria-label') || '').trim()) && gorunur(e)) { M.hazir = performance.now(); return; } } catch {} requestAnimationFrame(() => setTimeout(bak, 30)); };
  bak();
  // Geçiş: tam sayfa gezinmeyle gelen yeni belgede ilk boyamaya kadar süre
  try { const t0 = +sessionStorage.getItem('__t0'); if (t0) { sessionStorage.removeItem('__t0'); M.gecis = { tamSayfa: true, t0abs: t0 }; po('paint', e => { if (e.name === 'first-contentful-paint') M.gecis.ms = performance.timeOrigin + e.startTime - t0; }); } } catch {}
};

const med = a => { const b = a.filter(x => x != null && !Number.isNaN(x)).sort((x, y) => x - y); return b.length ? b[Math.floor((b.length - 1) / 2)] + (b.length % 2 ? 0 : (b[b.length / 2] - b[(b.length - 1) / 2]) / 2) : null; };

async function kur(page) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Network.enable');
  await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 150, downloadThroughput: 1.6 * 1024 * 1024 / 8, uploadThroughput: 750 * 1024 / 8 });
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  const reqs = new Map();
  cdp.on('Network.requestWillBeSent', e => { if (!reqs.has(e.requestId) || e.redirectResponse) reqs.set(e.requestId, { id: e.requestId, url: e.request.url, method: e.request.method, type: e.type, ts: e.timestamp, rb: e.request.renderBlocking ?? null, init: e.initiator?.type, dec: 0 }); });
  cdp.on('Network.responseReceived', e => { const r = reqs.get(e.requestId); if (!r) return; const h = Object.fromEntries(Object.entries(e.response.headers).map(([k, v]) => [k.toLowerCase(), v])); Object.assign(r, { status: e.response.status, mime: e.response.mimeType, sw: e.response.fromServiceWorker, disk: e.response.fromDiskCache, cc: h['cache-control'] ?? null, cf: h['cf-cache-status'] ?? null, ce: h['content-encoding'] ?? null, type: e.type || r.type }); });
  cdp.on('Network.dataReceived', e => { const r = reqs.get(e.requestId); if (r) r.dec += e.dataLength; });
  cdp.on('Network.loadingFinished', e => { const r = reqs.get(e.requestId); if (r) { r.enc = e.encodedDataLength; r.te = e.timestamp; } });
  cdp.on('Network.loadingFailed', e => { const r = reqs.get(e.requestId); if (r) { r.fail = e.errorText; r.te = e.timestamp; } });
  return { cdp, reqs };
}

async function yukle(page, net, url) {
  await page.evaluate(() => { try { sessionStorage.removeItem('__t0'); } catch {} }).catch(() => {});
  net.reqs.clear();
  const t = Date.now();
  let hata = null, gezinme = null;
  try { await page.goto(url, { waitUntil: 'load', timeout: 60000 }); } catch (e) { gezinme = temizHata(e.message.split('\n')[0]); hata = gezinme; }
  // hazır öğe görünene kadar (en çok 45 s), sonra 4 s daha bekle (geç gelen istekler, LCP)
  try { await page.waitForFunction(() => window.__m && window.__m.hazir != null, null, { timeout: 45000, polling: 200 }); } catch { hata = (hata || '') + ' hazir-zaman-asimi'; }
  await page.waitForTimeout(4000);
  const m = await page.evaluate(() => {
    const n = performance.getEntriesByType('navigation')[0] || {};
    return { ...window.__m, nav: { ttfb: n.responseStart, dcl: n.domContentLoadedEventEnd, load: n.loadEventEnd, type: n.type }, sw: !!(navigator.serviceWorker && navigator.serviceWorker.controller), url: location.origin + location.pathname, end: performance.now() };
  }).catch(e => ({ hata: temizHata(e.message.split('\n')[0]) }));
  const list = [...net.reqs.values()];
  const doc = list.find(r => r.type === 'Document') || list[0];
  const base = doc ? doc.ts : 0;
  const host = new URL(url).hostname.replace(/^www\./, '');
  if (m && Array.isArray(m.lcp)) m.lcp = m.lcp.map(x => ({ ...x, url: x.url ? temizAdres(x.url) : null }));
  if (m && m.loaf) m.loaf = m.loaf.map(x => ({ ...x, scripts: (x.scripts || []).map(s => ({ ...s, src: temizAdres(s.src) })) }));
  const reqs = list.map(r => ({ url: temizAdres(r.url).slice(0, 200), method: r.method, type: r.type, status: r.status, start: Math.round((r.ts - base) * 1000), end: r.te ? Math.round((r.te - base) * 1000) : null, enc: r.enc ?? 0, dec: r.dec, sw: r.sw, disk: r.disk, cc: r.cc, cf: r.cf, ce: r.ce, rb: r.rb, fail: r.fail, birinci: new URL(r.url, url).hostname.replace(/^www\./, '').endsWith(host) || r.url.startsWith('data:') }));
  return { hata, sure: Date.now() - t, ...m, gezinme, reqs };
}

function ozet(r) {
  const fcp = r.fcp;
  const lcp = r.lcp?.length ? r.lcp[r.lcp.length - 1] : null;
  const tbt = (r.lt || []).filter(x => fcp != null && x.t >= fcp).reduce((s, x) => s + Math.max(0, x.d - 50), 0);
  const tbtTum = (r.lt || []).reduce((s, x) => s + Math.max(0, x.d - 50), 0);
  const cls = (r.ls || []).reduce((s, x) => s + x.v, 0);
  const by = {}; let enc = 0, dec = 0;
  const real = (r.reqs || []).filter(q => !q.url.startsWith('data:'));
  for (const q of real) { const k = { Script: 'js', Stylesheet: 'css', Font: 'font', Image: 'img', Document: 'html', Fetch: 'xhr', XHR: 'xhr' }[q.type] || 'diger'; by[k] ??= { enc: 0, dec: 0, n: 0 }; by[k].enc += q.enc; by[k].dec += q.dec; by[k].n++; enc += q.enc; dec += q.dec; }
  const kritik = real.filter(q => fcp != null && q.start < fcp);
  return {
    ttfb: r.nav?.ttfb, fcp, lcp: lcp?.t ?? null, lcpEl: lcp?.el, lcpUrl: lcp?.url, hazir: r.hazir, tbt, tbtTum, uzunGorev: (r.lt || []).length, enUzun: Math.max(0, ...(r.lt || []).map(x => x.d)), cls, istek: real.length, enc, dec, by, kritikIstek: kritik.length,
    agdanGelen: real.filter(q => !q.sw && !q.disk && q.enc > 0).length, sw: r.sw, hata: r.hata,
  };
}

async function gecis(page, net, url, [ad, sel, txt]) {
  await yukle(page, net, url);
  const loc = sel.startsWith('role:') ? page.getByRole(sel.slice(5), { name: new RegExp(txt) }).first() : page.locator(sel).filter({ hasText: txt ? new RegExp(txt) : undefined }).first();
  if (!(await loc.count().catch(() => 0))) return { ad, bulunamadi: true };
  await page.evaluate(() => {
    const G = (window.__g = { t0: null, mut: null, boya: null });
    document.addEventListener('pointerdown', e => { if (G.t0 == null) { G.t0 = e.timeStamp; try { sessionStorage.setItem('__t0', String(performance.timeOrigin + e.timeStamp)); } catch {} } }, { capture: true });
    document.addEventListener('click', () => { if (G.t0 == null) { G.t0 = performance.now(); try { sessionStorage.setItem('__t0', String(performance.timeOrigin + G.t0)); } catch {} } }, { capture: true });
    new MutationObserver(() => { if (G.t0 != null && G.mut == null) { G.mut = performance.now(); requestAnimationFrame(() => setTimeout(() => { G.boya = performance.now(); }, 0)); } }).observe(document, { subtree: true, childList: true, attributes: true, characterData: true });
    addEventListener('hashchange', () => { if (G.t0 != null && G.mut == null) G.mut = performance.now(); });
  });
  const u0 = page.url();
  const popup = page.context().waitForEvent('page', { timeout: 3000 }).catch(() => null);
  try { await loc.click({ timeout: 8000 }); } catch (e) { return { ad, hata: temizHata(e.message.split('\n')[0]) }; }
  await page.waitForTimeout(3500);
  const p2 = await popup; if (p2) { await p2.close().catch(() => {}); return { ad, yeniSekme: true }; }
  const g = await page.evaluate(() => ({ g: window.__g || null, m: window.__m?.gecis || null, ev: (window.__m?.ev || []).filter(e => ['pointerdown', 'pointerup', 'click', 'mousedown', 'mouseup'].includes(e.name)) })).catch(e => ({ hata: temizHata(e.message.split('\n')[0]) }));
  if (g.m?.tamSayfa) return { ad, tamSayfa: true, ms: g.m.ms != null ? Math.round(g.m.ms) : null, url: temizAdres(page.url()) };
  const G = g.g || {};
  const inp = Math.max(0, ...(g.ev || []).map(e => e.d));
  return { ad, tamSayfa: false, degisim: G.mut != null ? Math.round(G.mut - G.t0) : null, boyama: G.boya != null ? Math.round(G.boya - G.t0) : null, inp: inp || null, urlDegisti: page.url() !== u0 };
}

const out = { site, url: temizAdres(URL0), yerel: YEREL, spec, tarih: new Date().toISOString(), kosu: [] };
const baslat = { args: ['--disable-extensions'] };
if (process.env.CHROME) baslat.executablePath = process.env.CHROME;
for (let i = 0; i < N; i++) {
  let b = null;
  try {
    b = await chromium.launch(baslat);
    const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, locale: 'tr-TR', deviceScaleFactor: 3, serviceWorkers: YEREL ? 'block' : 'allow' });
    // Yerel kipte yalnız loopback ve data:/blob: isteklerine izin; dış bağlantılar kesilir.
    if (YEREL) await ctx.route('**/*', (r) => { const u = r.request().url(); return (loopbackMi(u) || u.startsWith('data:') || u.startsWith('blob:')) ? r.continue() : r.abort('blockedbyclient'); });
    await ctx.addInitScript(INIT, spec.hazir);
    const page = await ctx.newPage();
    const net = await kur(page);
    const soguk = GONLY ? null : await yukle(page, net, URL0);
    const sicak = GONLY ? null : await yukle(page, net, URL0);
    const gec = [];
    for (const g of spec.gec) gec.push(await gecis(page, net, URL0, g));
    if (GONLY) { out.kosu.push({ gec }); console.log(site, i, JSON.stringify(gec)); }
    else { out.kosu.push({ soguk, sicak, gec, sogukOzet: ozet(soguk), sicakOzet: ozet(sicak) });
    console.log(site, i, JSON.stringify({ s: ozet(soguk), w: ozet(sicak) }).slice(0, 400), JSON.stringify(gec)); }
  } catch (e) { const msg = temizHata(e.message.split('\n')[0]); console.log(site, i, 'HATA', msg); out.kosu.push({ hata: msg }); }
  if (b) await b.close().catch(() => {});
}
// Geçerli koşu. Tam kipte: soğuk ve sıcak açılışın ikisinde de hazır öğe görüldü ve gezinme hatası yok.
// Geçiş kipinde: en az bir geçişte gerçek süre ölçüldü (degisim, boyama ya da tam sayfa ms); yalnız bulunan düğme ya da yeni sekme sayılmaz.
const acilisGecerli = (r) => !!r && r.hazir != null && !r.gezinme;
const sure = (v) => typeof v === 'number' && Number.isFinite(v);
const gecisOlculdu = (g) => !!g && !g.yeniSekme && (sure(g.degisim) || sure(g.boyama) || sure(g.ms));
const gecerli = out.kosu.filter(k => !k.hata && (GONLY ? (k.gec || []).some(gecisOlculdu) : acilisGecerli(k.soguk) && acilisGecerli(k.sicak)));
out.gecerliKosu = gecerli.length;
if (GONLY) {
  writeFileSync(`ham-${site}-gecis.json`, JSON.stringify(out, null, 1));
  if (!gecerli.length) { console.error(`BAŞARISIZ: ${site} için ${N} koşunun hiçbiri geçerli değil`); process.exit(1); }
  process.exit(0);
}
const K = gecerli; // medyan yalnız geçerli koşulardan
const alan = ['ttfb', 'fcp', 'lcp', 'hazir', 'tbt', 'tbtTum', 'cls', 'istek', 'enc', 'dec', 'kritikIstek', 'agdanGelen', 'enUzun'];
out.medyan = {};
for (const w of ['sogukOzet', 'sicakOzet']) { out.medyan[w] = {}; for (const a of alan) out.medyan[w][a] = med(K.map(k => k[w][a])); out.medyan[w].jsEnc = med(K.map(k => k[w].by.js?.enc ?? 0)); out.medyan[w].jsDec = med(K.map(k => k[w].by.js?.dec ?? 0)); }
out.medyan.gecis = spec.gec.map(([ad]) => { const g = K.map(k => k.gec.find(x => x.ad === ad)).filter(Boolean); return { ad, degisim: med(g.map(x => x.degisim ?? x.ms)), boyama: med(g.map(x => x.boyama ?? x.ms)), inp: med(g.map(x => x.inp)), tamSayfa: g.some(x => x.tamSayfa), not: g.filter(x => x.bulunamadi || x.hata || x.yeniSekme).map(x => x.hata || (x.bulunamadi ? 'bulunamadı' : 'yeni sekme')) }; });
writeFileSync(`ham-${site}.json`, JSON.stringify(out, null, 1));
console.log('MEDYAN', site, JSON.stringify(out.medyan));
if (!gecerli.length) { console.error(`BAŞARISIZ: ${site} için ${N} koşunun hiçbiri geçerli değil`); process.exit(1); }
