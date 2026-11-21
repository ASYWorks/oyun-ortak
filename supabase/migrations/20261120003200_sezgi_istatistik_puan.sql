-- PU-7 g (Beat Greedy, 16 Kasım 2026): profil Keşif kartı puan v1 alanları. Eski alanlar aynen kalır.
--   avg_puan: kapıdan (sezgi.yeni_puan) sonraki günlerde gün puan toplamının ortalaması; gün yoksa null.
--   recent_puan: son 14 günün gün puan toplamı, eskiden bugüne; oynanmayan ya da kapıdan önceki gün null.
--   games[oyun].avg_puan: kapıdan sonraki Keşif denemelerinde ham puan ortalaması.
create or replace function sezgi.my_daily_stats() returns jsonb
language sql stable security definer set search_path = sezgi as $$
  with g as (
    select game, day, score, rank, case when yeni_puan(day) then puan end as puan
    from board_game_day where user_id = auth.uid()
  ), d as (
    select day, total, rank, case when yeni_puan(day) then puan end as puan from board_day where user_id = auth.uid()
  ), runs as (
    -- Ardışık günlerde gün − sıra sabittir: her grup bir seri.
    select count(*)::int as len, max(day) as last_day
    from (select day, day - (row_number() over (order by day))::int as grp from d) s
    group by grp
  )
  select jsonb_build_object(
    -- Şimdiki seri bugün ya da dünle biter: bugün henüz oynamayanın serisi gece yarısı kopmaz.
    'streak', coalesce((select max(len) from runs where last_day >= istanbul_today() - 1), 0),
    'best_streak', coalesce((select max(len) from runs), 0),
    'days', (select count(*)::int from d),
    'avg_total', (select round(avg(total))::int from d),
    'avg_puan', (select avg(puan) from d where puan is not null),
    'best_day_rank', (select min(rank)::int from d),
    'games', coalesce((
      select jsonb_object_agg(game, jsonb_build_object(
        'days', n, 'avg', avg_score, 'best_rank', best_rank, 'avg_puan', avg_puan))
      from (select game, count(*)::int as n, round(avg(score))::int as avg_score, min(rank)::int as best_rank,
                   avg(puan) as avg_puan
            from g group by game) x), '{}'::jsonb),
    -- Son 14 gün, eskiden bugüne; oynanmayan gün null.
    'recent', (
      select jsonb_agg(d.total order by s.day)
      from generate_series(istanbul_today() - 13, istanbul_today(), interval '1 day') as s(day)
      left join d on d.day = s.day::date),
    'recent_puan', (
      select jsonb_agg(d.puan order by s.day)
      from generate_series(istanbul_today() - 13, istanbul_today(), interval '1 day') as s(day)
      left join d on d.day = s.day::date)
  )
$$;
