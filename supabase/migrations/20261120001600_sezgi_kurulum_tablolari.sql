-- BG-5 (15 Kasım 2026): kurulum başına günde bir hesap Beat Greedy'nin kendi günlük tablolarına da (Keşif, Yarış,
-- lig günlük). submit_attempt her teslimde sezgi.kurulum_isaretle(deneme, cihaz) çağırır; kurulum o gün başka hesaba
-- aitse deneme 'kurulum' bayrağı alır ve günlük tablolarda sayılmaz (oyuncunun kendi sonucu kalır). Gün anahtarı
-- gun_toplami_yaz ile aynı (oyun 'sezgi', bulmaca günü): Keşif ve Yarış aynı kurulumda aynı hesaba ayrılır.

create function sezgi.kurulum_isaretle(p_attempt bigint, p_cihaz text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare u uuid; gun date;
begin
  select a.user_id, p.day into u, gun from sezgi.attempts a join sezgi.daily_puzzles p on p.id = a.puzzle_id where a.id = p_attempt;
  if u is null or p_cihaz is null then return false; end if;
  if ortak.kurulum_baska_hesap('sezgi', p_cihaz, gun::text, u) then
    update sezgi.attempts set flags = array_append(flags, 'kurulum') where id = p_attempt and not ('kurulum' = any (flags));
    return true;
  end if;
  return false;
end $$;
revoke execute on function sezgi.kurulum_isaretle(bigint, text) from public, anon, authenticated;

create or replace view sezgi.board_game_day as
select p.game, p.day, a.user_id, pr.username, pr.avatar, case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.score end as score, a.duration_ms, a.submitted_at,
       rank() over (partition by a.puzzle_id
         order by round((a.value * sezgi.game_sign(p.game))::numeric, 6) desc nulls last,
                  a.duration_ms asc, a.submitted_at asc) as rank,
       case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.value end as value
from sezgi.attempts a
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where p.kind = 'daily' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags));

create or replace view sezgi.board_day as
select p.day, a.user_id, pr.username, pr.avatar,
       sum(a.score)::int as total, sum(a.duration_ms)::bigint as total_ms, count(*)::int as games,
       rank() over (partition by p.day order by sum(a.score) desc, sum(a.duration_ms) asc) as rank
from sezgi.attempts a
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where p.kind = 'daily' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags))
group by p.day, a.user_id, pr.username, pr.avatar;

create or replace view sezgi.league_board_game_day as
select m.league_id, p.game, p.day, a.user_id, pr.username, pr.avatar, case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.score end as score, a.duration_ms, a.submitted_at,
       rank() over (partition by m.league_id, a.puzzle_id
         order by round((a.value * sezgi.game_sign(p.game))::numeric, 6) desc nulls last,
                  a.duration_ms asc, a.submitted_at asc) as rank,
       case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.value end as value
from sezgi.league_members me
join sezgi.league_members m on m.league_id = me.league_id
join sezgi.attempts a on a.user_id = m.user_id
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where me.user_id = auth.uid() and p.kind = 'daily' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags));

create or replace view sezgi.league_board_day as
select m.league_id, p.day, a.user_id, pr.username, pr.avatar,
       sum(a.score)::int as total, sum(a.duration_ms)::bigint as total_ms, count(*)::int as games,
       rank() over (partition by m.league_id, p.day order by sum(a.score) desc, sum(a.duration_ms) asc) as rank
from sezgi.league_members me
join sezgi.league_members m on m.league_id = me.league_id
join sezgi.attempts a on a.user_id = m.user_id
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where me.user_id = auth.uid() and p.kind = 'daily' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags))
group by m.league_id, p.day, a.user_id, pr.username, pr.avatar;

create or replace view sezgi.board_race as
select p.day, p.game, a.user_id, pr.username, pr.avatar, a.value, a.duration_ms, a.hints,
       coalesce(a.reached, false) as reached,
       case when a.reached then a.duration_ms::bigint + a.hints * 30000 end as race_ms,
       a.submitted_at,
       rank() over (partition by a.puzzle_id
         order by case when a.reached then a.duration_ms::bigint + a.hints * 30000 end asc nulls last,
                  round((a.value * sezgi.game_sign(p.game))::numeric, 6) desc nulls last,
                  a.duration_ms asc, a.submitted_at asc) as rank
from sezgi.attempts a
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where p.kind = 'race' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags));

create or replace view sezgi.board_race_day as
select p.day, a.user_id, pr.username, pr.avatar,
       count(*) filter (where a.reached)::int as goals,
       sum(a.duration_ms::bigint + a.hints * 30000) filter (where a.reached) as race_ms,
       count(*)::int as games,
       rank() over (partition by p.day
         order by count(*) filter (where a.reached) desc,
                  sum(a.duration_ms::bigint + a.hints * 30000) filter (where a.reached) asc nulls last) as rank
from sezgi.attempts a
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where p.kind = 'race' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags))
group by p.day, a.user_id, pr.username, pr.avatar;
