-- Beat Greedy adil puan hazırlığı (ISTEKLER PU-7 a, c, d; kurucu onayı 16 Kasım 2026, sezgi K119).
-- Formül ve görünümler bot raporundan sonra ayrı göçte (PU-7 b, e).
-- a) Yeni puan alanları: submit_attempt doldurur; eski satırlarda boş.
alter table sezgi.attempts
  add column if not exists puan numeric,
  add column if not exists puan_surumu int,
  add column if not exists ayrinti jsonb;

-- c) Yarış ipucu hakkı 3: hak bitince 'ipucu_hakki_bitti' hatası (race_hint bunu oyuncuya metinle döndürür).
--    Tek update koşullu olduğu için aynı anda gelen istekler hakkı aşamaz.
create or replace function sezgi.count_hint(p_attempt bigint, p_user uuid) returns int
language plpgsql set search_path = sezgi as $$
declare n int;
begin
  update attempts a set hints = a.hints + 1
  from daily_puzzles p
  where a.id = p_attempt and a.user_id = p_user and p.id = a.puzzle_id and p.kind = 'race'
    and a.status = 'started' and now() < attempt_deadline(p.day) and a.hints < 3
  returning a.hints into n;
  if n is null and exists (select 1 from attempts where id = p_attempt and user_id = p_user and hints >= 3 and status = 'started') then
    raise exception 'ipucu_hakki_bitti' using errcode = 'P0001';
  end if;
  return n;
end $$;

-- d) Ligde eşitlik bozucu: en iyi günlerin ikincil toplamı (küçük iyi).
update ortak.oyunlar set ayarlar = jsonb_set(ayarlar, '{lig,esitlik}', '"ikincil"') where id = 'sezgi' and ayarlar ? 'lig';
