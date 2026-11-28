// gizli-ile.mjs: ayrıştırma ve maskeleme (gerçek gizli dosya okunmaz).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { envOku, parolaOku, maskeleyici } from './gizli-ile.mjs';

test('env satırları: export, tırnak, yorum', () => {
  assert.deepEqual(envOku('# yorum\nexport A_KEY="abc123def"\nB=\'x y z\'\n  C = 42\nbozuk satır'), { A_KEY: 'abc123def', B: 'x y z', C: '42' });
});
test('supabase-parolalar: proje adına göre PGPASSWORD', () => {
  assert.deepEqual(parolaOku('oyun-canli Gizli-Parola-1\noyun-test Test-Parola-2\nbaşka x'), { PGPASSWORD_CANLI: 'Gizli-Parola-1', PGPASSWORD_TEST: 'Test-Parola-2' });
});
test('çıktıda geçen değer maskelenir; kısa değerler (<6) dokunulmaz', () => {
  const m = maskeleyici(['abc123def', '42', 'abc123def-uzun']);
  assert.equal(m('anahtar=abc123def-uzun ve abc123def, sayı 42'), 'anahtar=[GİZLİ] ve [GİZLİ], sayı 42');
});
