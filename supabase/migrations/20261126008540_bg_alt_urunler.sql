-- Göç 8540: Beat Greedy alt oyun ürünleri (BG-13; kurucu 26 Kasım, sezgi/docs/YENI_YAPI.md K141). Oyun başına 99 TL ürün
-- beatgreedy_<oyun> → hak alt_<oyun>; hepsi paketi (499 TL) beatgreedy_paket_tam → paket_tam. Fiyat mağazada tanımlanır.
insert into ortak.urunler (urun, oyun_id, hak) values
  ('beatgreedy_kestirme', 'sezgi', 'alt_kestirme'),
  ('beatgreedy_frekans', 'sezgi', 'alt_frekans'),
  ('beatgreedy_canta', 'sezgi', 'alt_canta'),
  ('beatgreedy_boru', 'sezgi', 'alt_boru'),
  ('beatgreedy_kapsama', 'sezgi', 'alt_kapsama'),
  ('beatgreedy_dugun', 'sezgi', 'alt_dugun'),
  ('beatgreedy_kutula', 'sezgi', 'alt_kutula'),
  ('beatgreedy_yilan', 'sezgi', 'alt_yilan'),
  ('beatgreedy_kasa', 'sezgi', 'alt_kasa'),
  ('beatgreedy_yufka', 'sezgi', 'alt_yufka'),
  ('beatgreedy_harman', 'sezgi', 'alt_harman'),
  ('beatgreedy_bostan', 'sezgi', 'alt_bostan'),
  ('beatgreedy_halat', 'sezgi', 'alt_halat'),
  ('beatgreedy_aniz', 'sezgi', 'alt_aniz'),
  ('beatgreedy_dedikodu', 'sezgi', 'alt_dedikodu'),
  ('beatgreedy_bayram', 'sezgi', 'alt_bayram'),
  ('beatgreedy_paket_tam', 'sezgi', 'paket_tam')
on conflict do nothing;
