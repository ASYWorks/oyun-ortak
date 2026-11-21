-- BG-11 (Beat Greedy, 15 Kasım 2026): Keşif ve Yarış 8'den 16 oyuna. sezgi.game_sign büyük değerin iyi olduğu oyunlar
-- için 1 döner (motorda direction 'max'): eski canta, yilan; yeni bostan, aniz, dedikodu, bayram. Yeni küçük-iyi
-- oyunlar (kasa, yufka, harman, halat) -1 ile kalır. Başka bir oyun listesi ya da üst sınır yok (deneme başlatma,
-- tablolar, lig gün toplamı oyun sayısından bağımsız; puan oyun başına 0–1000).
create or replace function sezgi.game_sign(p_game text) returns int
language sql immutable as $$
  select case when p_game in ('canta', 'yilan', 'bostan', 'aniz', 'dedikodu', 'bayram') then 1 else -1 end
$$;
