export const SITES = {
  halka: 'https://www.halkakelime.com/',
  beatgreedy: 'https://beatgreedy.com/',
  sticky: 'https://stickyten.com/',
  ense: 'https://ense-nasil-olsun.asyworks.com/',
  sahte: 'https://sahte-masasi.asyworks.com/',
  remzle: 'https://remzle.asyworks.com/',
  ezber: 'https://ezber-bozan.asyworks.com/',
  koz: 'https://koz-hesabi.asyworks.com/',
  kapi: 'https://kapi-ustasi.asyworks.com/',
  mahalle: 'https://mahalle-donusumu.asyworks.com/',
  ifade: 'https://ifade-kati.asyworks.com/',
  hopkoala: 'https://hopkoala.com/',
};

// Playwright yalnız ölçüm başlarken yüklenir (--help yüklemez). Öncelik: PLAYWRIGHT_MODULE (mutlak yol ya da file: URL), sonra
// paket adı 'playwright'. Başka oyun deposunun node_modules'una sabit yol yok.
export async function playwrightYukle() {
  const ozel = process.env.PLAYWRIGHT_MODULE;
  let hedef = 'playwright';
  if (ozel) {
    const { isAbsolute } = await import('node:path');
    const { pathToFileURL } = await import('node:url');
    if (ozel.startsWith('file:')) hedef = ozel;
    else if (isAbsolute(ozel)) hedef = pathToFileURL(ozel).href;
    else throw new Error('PLAYWRIGHT_MODULE mutlak yol ya da file: URL olmalı');
  }
  try { return await import(hedef); }
  catch (e) { throw new Error(`Playwright yüklenemedi (${hedef}): npm i -D playwright ya da PLAYWRIGHT_MODULE ver. ${e.message.split('\n')[0]}`); }
}

// Yerel deneme: yalnız loopback adresi (http(s)://localhost | 127.0.0.1 | [::1]). Keyfi uzak adres kabul edilmez.
export function yerelAdres(deger) {
  let u;
  try { u = new URL(deger); } catch { throw new Error('HIZ_TEST_URL geçerli bir adres değil'); }
  if (!['http:', 'https:'].includes(u.protocol)) throw new Error('HIZ_TEST_URL http ya da https olmalı');
  if (!['localhost', '127.0.0.1', '[::1]'].includes(u.hostname)) throw new Error('HIZ_TEST_URL yalnız loopback olabilir (localhost, 127.0.0.1, [::1])');
  if (u.username || u.password) throw new Error('HIZ_TEST_URL kullanıcı bilgisi içeremez');
  return u.href;
}
export const loopbackMi = (adres) => { try { return ['localhost', '127.0.0.1', '[::1]'].includes(new URL(adres).hostname); } catch { return false; } };
