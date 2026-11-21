-- Puan ölçeği 0–100 tamsayı (kurucu, 16 Kasım 2026; ADIL_PUAN §1, önceki 0–5 × 20). Hemen geçerli.
-- Beat Greedy: seviye puanı 0–100 tamsayı (record_level ondalıklı ya da aralık dışı puanı 'bad_puan' ile reddeder);
-- board_levels eşitlik bozucusu master3 = puanı 100 olan seviye sayısı (Bölüm 1–4). Canlıda puanlı satır yoktu.
create or replace function sezgi.record_level(
  p_user uuid, p_game text, p_level int, p_raw_stars int, p_value double precision, p_puan numeric default null
) returns jsonb language plpgsql set search_path = sezgi set extra_float_digits = 1 as $$
declare
  r level_verified;
begin
  if not exists (select from profiles where id = p_user) then
    return jsonb_build_object('error', 'no_profile');
  end if;
  if p_puan is not null and (p_puan < 0 or p_puan > 100 or p_puan <> trunc(p_puan)) then
    return jsonb_build_object('error', 'bad_puan');
  end if;
  insert into level_verified as v (user_id, game, level, raw_stars, value, puan)
  values (p_user, p_game, p_level, p_raw_stars, p_value, p_puan)
  on conflict (user_id, game, level) do update
    set raw_stars = greatest(v.raw_stars, excluded.raw_stars),
        value = case when excluded.raw_stars > v.raw_stars then excluded.value else v.value end,
        puan = greatest(v.puan, excluded.puan),
        verified_at = now()
    where excluded.raw_stars > v.raw_stars or excluded.puan > coalesce(v.puan, -1);
  select * into r from level_verified where user_id = p_user and game = p_game and level = p_level;
  return jsonb_build_object('game', r.game, 'level', r.level, 'raw_stars', r.raw_stars,
    'value', r.value, 'puan', r.puan, 'verified_at', r.verified_at);
end $$;

create or replace view sezgi.board_levels as
with t as (
  select user_id, coalesce(game, 'all') as game, sum(raw_stars)::int as stars,
         (count(*) filter (where puan >= 100))::int as master3,
         max(verified_at) as reached_at,
         sum(puan) as puan
  from sezgi.level_verified
  where level < 4000
  group by grouping sets ((user_id, game), (user_id))
)
select t.game, t.user_id, pr.username, pr.avatar, t.stars, t.master3, t.reached_at,
       rank() over (partition by t.game
         order by case when sezgi.yeni_puan(sezgi.istanbul_today()) then t.puan else t.stars end desc nulls last,
                  case when sezgi.yeni_puan(sezgi.istanbul_today()) then t.master3 else 0 end desc,
                  t.reached_at asc) as rank,
       t.puan
from t join sezgi.profiles pr on pr.id = t.user_id
where t.stars > 0 or t.puan > 0;
