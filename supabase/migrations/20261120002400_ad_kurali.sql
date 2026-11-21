-- Ortak kullanıcı adı kuralı (bütün oyunlar, kurucu 2026-11-15):
--   3–20 karakter; harf (Türkçe harfler dahil) ve rakam; özel karakter yalnız _ ve .
--   boşluk yok; _ ve . başta, sonda ve art arda olamaz; en az bir harf.
-- Oyun ayarındaki en_az/en_cok bu sınırların dışına çıkamaz (yalnız daraltabilir).
create or replace function ortak.ad_bicimi(ad text, en_az int, en_cok int) returns boolean
language sql immutable set search_path = '' as $$
  select char_length(ad) between greatest(en_az, 3) and least(en_cok, 20)
     and ad ~ '^[A-Za-z0-9ÇĞİÖŞÜÂÎÛçğıöşüâîû]+([._][A-Za-z0-9ÇĞİÖŞÜÂÎÛçğıöşüâîû]+)*$'
     and ad ~ '[A-Za-zÇĞİÖŞÜÂÎÛçğıöşüâîû]'
$$;

-- Her oyunun ayarı ortak sınırlara çekilir (istemci bu değerleri gösterir).
update ortak.oyunlar
set ayarlar = jsonb_set(ayarlar, '{ad}', coalesce(ayarlar -> 'ad', '{}') || '{"en_az": 3, "en_cok": 20}');
