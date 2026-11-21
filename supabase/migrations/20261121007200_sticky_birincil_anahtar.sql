-- Sticky Ten, 21 Kasım (danışman: birincil anahtarsız tablo; Sticky oturumu önerisi). İki tablo da canlıda ve testte boştu.
-- rating_log: kimlik sütunu birincil anahtar; ayrıca oyun başına oyuncu tek satır (puanli_sonuc_yaz'ın tek yazım güvencesi
-- tabloda da). ST-10 öncesi satırlarda oyun boş olabildiği için kısmi.
-- rated_pairs: doğal anahtar yok (aynı ikili farklı oyunlarda tekrarlanır); kimlik sütunu birincil anahtar.
alter table sticky.rating_log add column id bigint generated always as identity primary key;
create unique index rating_log_oyun_oyuncu on sticky.rating_log (oyun, user_id) where oyun is not null;
alter table sticky.rated_pairs add column id bigint generated always as identity primary key;
