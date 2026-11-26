-- Göç 8550: Remzle alt oyun ürünleri (RZ-10; kurucu 26 Kasım): oyun başına 99 TL ürün remzle_<motor> → hak alt_<motor>
-- (22 motor, sifre-burosu/app/levels/model.ts SUBGAMES); Hepsi paketi (499 TL) remzle_paket_tam → paket_tam.
-- Korumalı kova kopyası (alt_<motor>/bolum/) ayrı iş; fiyat mağazada tanımlanır.
insert into ortak.urunler (urun, oyun_id, hak) values
  ('remzle_morse', 'remzle', 'alt_morse'),
  ('remzle_caesar', 'remzle', 'alt_caesar'),
  ('remzle_atbash', 'remzle', 'alt_atbash'),
  ('remzle_vigenere', 'remzle', 'alt_vigenere'),
  ('remzle_cryptogram', 'remzle', 'alt_cryptogram'),
  ('remzle_vault', 'remzle', 'alt_vault'),
  ('remzle_wordmind', 'remzle', 'alt_wordmind'),
  ('remzle_vowels', 'remzle', 'alt_vowels'),
  ('remzle_numbers', 'remzle', 'alt_numbers'),
  ('remzle_columnar', 'remzle', 'alt_columnar'),
  ('remzle_railfence', 'remzle', 'alt_railfence'),
  ('remzle_nullcipher', 'remzle', 'alt_nullcipher'),
  ('remzle_affine', 'remzle', 'alt_affine'),
  ('remzle_binary', 'remzle', 'alt_binary'),
  ('remzle_keyboard', 'remzle', 'alt_keyboard'),
  ('remzle_keypad', 'remzle', 'alt_keypad'),
  ('remzle_anagram', 'remzle', 'alt_anagram'),
  ('remzle_polybius', 'remzle', 'alt_polybius'),
  ('remzle_pigpen', 'remzle', 'alt_pigpen'),
  ('remzle_alphametic', 'remzle', 'alt_alphametic'),
  ('remzle_acrostic', 'remzle', 'alt_acrostic'),
  ('remzle_route', 'remzle', 'alt_route'),
  ('remzle_paket_tam', 'remzle', 'paket_tam')
on conflict do nothing;
