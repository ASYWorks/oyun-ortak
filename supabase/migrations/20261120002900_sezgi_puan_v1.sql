-- Adil puan v1 (ADIL_PUAN.md; ISTEKLER PU-8, PU-7 b, e, f; Beat Greedy v1 kurucu onayı 16 Kasım 2026, sezgi PUAN §7).
--
-- 1) PU-8 ortak puan ayarı: oyun × sürüm × geçerli Pazartesi × ayar (oyuna özgü jsonb; Beat Greedy
--    {"hedef_ms": {"<oyun>": [k0..k6]}}). Sürüm yalnız Pazartesi başlar; süren ya da kapanmış haftanın sürümü
--    eklenemez, değişmez, silinmez. Okuma: ortak.puan_ayari(oyun, gün) o günün sürümünü verir (yalnız servis rolü).
-- 2) Tarih kapısı: Beat Greedy'de ilk sürümün geçerli günü kapıdır. Kapıdan önceki günler ve haftalar eski hesapla
--    kalır (score, ham süre); kapıdan itibaren yeni puan (attempts.puan, ayrinti.lt). Ayar satırı yokken her şey eski.
-- 3) PU-7 b tablolar: eski sütunlar aynen kalır (eski istemci bozulmasın), sona puan ve ikincil eklenir; sıra kapıya göre.
--    Keşif oyun tablosu değerle kalır (K89). Gün: ham puan toplamı, eşitlikte Σ lt. Hafta: en iyi 5 gün.
--    Tüm zamanlar: kapı geçildiyse yalnız kapıdan sonraki günler (eski ve yeni ölçek karışmasın), son 30 günün en iyi 20'si.
--    Yarış: ham puan azalan, eşitlikte lt.
-- 4) PU-7 f seviyeler: puan sunucunun doğruladığı level_verified'da (level_progress istemcinin kendi yazdığı tablo,
--    sıralamaya giremez; orada yalnız gösterim için). board_levels kapı geçilince puan toplamıyla, eşitlikte puanı 5
--    olan seviye sayısı (master3) ile sıralanır.
-- 5) PU-7 e kalibrasyon: sezgi.kalibrasyon(bas, bit), yalnız servis rolü.

-- ---------------------------------------------------------------- 1
create table ortak.puan_ayar (
  oyun_id text not null references ortak.oyunlar on delete cascade,
  surum int not null check (surum > 0),
  gecerli date not null check (extract(isodow from gecerli) = 1),
  ayar jsonb not null,
  olusturma timestamptz not null default now(),
  primary key (oyun_id, surum),
  unique (oyun_id, gecerli)
);
alter table ortak.puan_ayar enable row level security;

-- Süren ya da kapanmış hafta değişmez; sürüm ve gün birlikte artar. Test ve acil durum için oturumda
-- set ortak.puan_ayar_serbest = 'acik' denetimi atlar.
create function ortak.puan_ayar_denetle() returns trigger
language plpgsql set search_path = '' as $$
declare bugun date := (now() at time zone 'Europe/Istanbul')::date;
begin
  if current_setting('ortak.puan_ayar_serbest', true) = 'acik' then return coalesce(new, old); end if;
  if tg_op <> 'INSERT' and old.gecerli <= bugun then raise exception 'puan_ayar_kapali'; end if;
  if tg_op = 'DELETE' then return old; end if;
  if new.gecerli <= bugun then raise exception 'puan_ayar_gecmis'; end if;
  if exists (select 1 from ortak.puan_ayar p where p.oyun_id = new.oyun_id and p.surum <> new.surum
             and (p.surum < new.surum) <> (p.gecerli < new.gecerli)) then
    raise exception 'puan_ayar_sira';
  end if;
  return new;
end $$;
create trigger puan_ayar_denetle before insert or update or delete on ortak.puan_ayar
  for each row execute function ortak.puan_ayar_denetle();
revoke execute on function ortak.puan_ayar_denetle() from public, anon, authenticated;

create function ortak.puan_ayari(p_oyun text, p_gun date) returns table (surum int, gecerli date, ayar jsonb)
language sql stable security definer set search_path = '' as $$
  select p.surum, p.gecerli, p.ayar from ortak.puan_ayar p
  where p.oyun_id = p_oyun and p.gecerli <= p_gun order by p.gecerli desc limit 1
$$;
revoke all on ortak.puan_ayar from public, anon, authenticated;
grant all on ortak.puan_ayar to service_role;
revoke execute on function ortak.puan_ayari(text, date) from public, anon, authenticated;
grant execute on function ortak.puan_ayari(text, date) to service_role;

-- ---------------------------------------------------------------- 2
create function sezgi.yeni_puan(p_gun date) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from ortak.puan_ayar where oyun_id = 'sezgi' and gecerli <= p_gun)
$$;
grant execute on function sezgi.yeni_puan(date) to anon, authenticated, service_role;

-- ---------------------------------------------------------------- 3
drop view sezgi.league_board_week, sezgi.league_board_all_time;
drop materialized view sezgi.board_week, sezgi.board_all_time;

create or replace view sezgi.board_game_day as
select p.game, p.day, a.user_id, pr.username, pr.avatar, case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.score end as score, a.duration_ms, a.submitted_at,
       rank() over (partition by a.puzzle_id
         order by round((a.value * sezgi.game_sign(p.game))::numeric, 6) desc nulls last,
                  a.duration_ms asc, a.submitted_at asc) as rank,
       case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.value end as value,
       case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.puan end as puan
from sezgi.attempts a
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where p.kind = 'daily' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags));

create or replace view sezgi.board_day as
select p.day, a.user_id, pr.username, pr.avatar,
       sum(a.score)::int as total, sum(a.duration_ms)::bigint as total_ms, count(*)::int as games,
       rank() over (partition by p.day
         order by case when sezgi.yeni_puan(p.day) then sum(a.puan) else sum(a.score) end desc nulls last,
                  case when sezgi.yeni_puan(p.day) then sum((a.ayrinti ->> 'lt')::numeric) else sum(a.duration_ms) end asc nulls last) as rank,
       sum(a.puan) as puan, sum((a.ayrinti ->> 'lt')::numeric) as ikincil
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
       case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.value end as value,
       case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.puan end as puan
from sezgi.league_members me
join sezgi.league_members m on m.league_id = me.league_id
join sezgi.attempts a on a.user_id = m.user_id
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where me.user_id = auth.uid() and p.kind = 'daily' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags));

create or replace view sezgi.league_board_day as
select m.league_id, p.day, a.user_id, pr.username, pr.avatar,
       sum(a.score)::int as total, sum(a.duration_ms)::bigint as total_ms, count(*)::int as games,
       rank() over (partition by m.league_id, p.day
         order by case when sezgi.yeni_puan(p.day) then sum(a.puan) else sum(a.score) end desc nulls last,
                  case when sezgi.yeni_puan(p.day) then sum((a.ayrinti ->> 'lt')::numeric) else sum(a.duration_ms) end asc nulls last) as rank,
       sum(a.puan) as puan, sum((a.ayrinti ->> 'lt')::numeric) as ikincil
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
         order by case when sezgi.yeni_puan(p.day) then -a.puan else case when a.reached then a.duration_ms::bigint + a.hints * 30000 end end asc nulls last,
                  case when sezgi.yeni_puan(p.day) then (a.ayrinti ->> 'lt')::numeric else -round((a.value * sezgi.game_sign(p.game))::numeric, 6) end asc nulls last,
                  a.duration_ms asc, a.submitted_at asc) as rank,
       a.puan, (a.ayrinti ->> 'lt')::numeric as ikincil
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
         order by case when sezgi.yeni_puan(p.day) then sum(a.puan) else count(*) filter (where a.reached) end desc nulls last,
                  case when sezgi.yeni_puan(p.day) then sum((a.ayrinti ->> 'lt')::numeric)
                       else sum(a.duration_ms::bigint + a.hints * 30000) filter (where a.reached) end asc nulls last) as rank,
       sum(a.puan) as puan, sum((a.ayrinti ->> 'lt')::numeric) as ikincil
from sezgi.attempts a
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where p.kind = 'race' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags))
group by p.day, a.user_id, pr.username, pr.avatar;

-- Hafta Pazartesi başlar (date_trunc('week')). Yeni haftalarda en iyi 5 gün; 10 dakikada bir yenilenir.
create materialized view sezgi.board_week as
with d as (
  select date_trunc('week', b.day)::date as week_start, b.user_id, b.username, b.avatar, b.total, b.total_ms, b.puan, b.ikincil,
         row_number() over (partition by date_trunc('week', b.day), b.user_id order by b.puan desc nulls last, b.ikincil asc nulls last) as n
  from sezgi.board_day b
), w as (
  select week_start, user_id, username, avatar, sezgi.yeni_puan(week_start) as yeni,
         sum(total)::int as total, sum(total_ms)::bigint as total_ms, count(*)::int as days,
         sum(puan) filter (where n <= 5) as puan, sum(ikincil) filter (where n <= 5) as ikincil
  from d group by week_start, user_id, username, avatar
)
select week_start, user_id, username, avatar, total, total_ms, days,
       rank() over (partition by week_start
         order by case when yeni then puan else total end desc nulls last,
                  case when yeni then ikincil else total_ms end asc nulls last) as rank,
       puan, ikincil
from w;
create unique index on sezgi.board_week (week_start, user_id);

-- Tüm zamanlar: son 30 günün (bugün dahil) en iyi 20 günü. Kapı geçildiyse yalnız kapıdan sonraki günler.
create materialized view sezgi.board_all_time as
with g as (select sezgi.yeni_puan(sezgi.istanbul_today()) as yeni),
best as (
  select b.*, g.yeni,
         row_number() over (partition by b.user_id
           order by case when g.yeni then b.puan else b.total end desc nulls last,
                    case when g.yeni then b.ikincil else b.total_ms end asc nulls last) as n
  from sezgi.board_day b, g
  where b.day > sezgi.istanbul_today() - 30 and b.day <= sezgi.istanbul_today()
    and (not g.yeni or sezgi.yeni_puan(b.day))
), t as (
  select user_id, username, avatar, bool_or(yeni) as yeni,
         sum(total)::int as total, sum(total_ms)::bigint as total_ms, count(*)::int as days,
         sum(puan) as puan, sum(ikincil) as ikincil
  from best where n <= 20 group by user_id, username, avatar
)
select user_id, username, avatar, total, total_ms, days,
       rank() over (order by case when yeni then puan else total end desc nulls last,
                             case when yeni then ikincil else total_ms end asc nulls last) as rank,
       puan, ikincil
from t;
create unique index on sezgi.board_all_time (user_id);

create view sezgi.league_board_week as
select m.league_id, b.week_start, b.user_id, b.username, b.avatar, b.total, b.total_ms, b.days,
       rank() over (partition by m.league_id, b.week_start
         order by case when sezgi.yeni_puan(b.week_start) then b.puan else b.total end desc nulls last,
                  case when sezgi.yeni_puan(b.week_start) then b.ikincil else b.total_ms end asc nulls last) as rank,
       b.puan, b.ikincil
from sezgi.league_members me
join sezgi.league_members m on m.league_id = me.league_id
join sezgi.board_week b on b.user_id = m.user_id
where me.user_id = auth.uid();

create view sezgi.league_board_all_time as
select m.league_id, b.user_id, b.username, b.avatar, b.total, b.total_ms, b.days,
       rank() over (partition by m.league_id
         order by case when sezgi.yeni_puan(sezgi.istanbul_today()) then b.puan else b.total end desc nulls last,
                  case when sezgi.yeni_puan(sezgi.istanbul_today()) then b.ikincil else b.total_ms end asc nulls last) as rank,
       b.puan, b.ikincil
from sezgi.league_members me
join sezgi.league_members m on m.league_id = me.league_id
join sezgi.board_all_time b on b.user_id = m.user_id
where me.user_id = auth.uid();

revoke all on sezgi.board_week, sezgi.board_all_time, sezgi.league_board_week, sezgi.league_board_all_time
  from public, anon, authenticated;
grant select on sezgi.board_week, sezgi.board_all_time, sezgi.league_board_week, sezgi.league_board_all_time to authenticated;
grant all on sezgi.board_week, sezgi.board_all_time, sezgi.league_board_week, sezgi.league_board_all_time to service_role;

-- Misafir (BG-12): yalnız gösterilecek sütunlar, user_id yok.
grant select (puan) on sezgi.board_game_day to anon;
grant select (puan, ikincil) on sezgi.board_day to anon;
grant select (week_start, username, avatar, total, total_ms, days, rank, puan, ikincil) on sezgi.board_week to anon;
grant select (username, avatar, total, total_ms, days, rank, puan, ikincil) on sezgi.board_all_time to anon;
grant select (puan, ikincil) on sezgi.board_race to anon;
grant select (puan, ikincil) on sezgi.board_race_day to anon;

-- ---------------------------------------------------------------- 4
alter table sezgi.level_verified add column if not exists puan numeric;
alter table sezgi.level_progress add column if not exists puan numeric;

-- p_puan: motorun levelPoints'i (ipucusuz, 0–5). Yıldız ve puan ayrı ayrı en iyisinde tutulur.
drop function sezgi.record_level(uuid, text, int, int, double precision);
create function sezgi.record_level(
  p_user uuid, p_game text, p_level int, p_raw_stars int, p_value double precision, p_puan numeric default null
) returns jsonb language plpgsql set search_path = sezgi set extra_float_digits = 1 as $$
declare
  r level_verified;
begin
  if not exists (select from profiles where id = p_user) then
    return jsonb_build_object('error', 'no_profile');
  end if;
  if p_puan is not null and (p_puan < 0 or p_puan > 5) then
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
revoke all on function sezgi.record_level(uuid, text, int, int, double precision, numeric) from public, anon, authenticated;
grant execute on function sezgi.record_level(uuid, text, int, int, double precision, numeric) to service_role;

create or replace view sezgi.board_levels as
with t as (
  select user_id, coalesce(game, 'all') as game, sum(raw_stars)::int as stars,
         (count(*) filter (where puan >= 5))::int as master3,
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
grant select (puan) on sezgi.board_levels to anon;

-- ---------------------------------------------------------------- 5
-- Bulmaca başına süre dağılımı, ipucu oranı ve puan; bayraklı denemeler dışarıda. Kaynak attempts.ayrinti
-- (sure_ms, hedef_ms, kademe, ipucu, lt). Zaman aralığı teslim zamanına göre.
create function sezgi.kalibrasyon(p_bas timestamptz, p_bit timestamptz)
returns table (kind text, game text, day date, kademe int, puan_surumu int, hedef_ms numeric, oyuncu bigint,
               sure_p10 numeric, sure_p25 numeric, sure_p50 numeric, sure_p75 numeric, sure_p90 numeric,
               ipucu_orani numeric, puan_p50 numeric, lt_p50 numeric)
language sql stable security definer set search_path = '' as $$
  select p.kind, p.game, p.day, max((a.ayrinti ->> 'kademe')::int), a.puan_surumu, max((a.ayrinti ->> 'hedef_ms')::numeric), count(*),
         percentile_cont(0.1) within group (order by (a.ayrinti ->> 'sure_ms')::numeric)::numeric,
         percentile_cont(0.25) within group (order by (a.ayrinti ->> 'sure_ms')::numeric)::numeric,
         percentile_cont(0.5) within group (order by (a.ayrinti ->> 'sure_ms')::numeric)::numeric,
         percentile_cont(0.75) within group (order by (a.ayrinti ->> 'sure_ms')::numeric)::numeric,
         percentile_cont(0.9) within group (order by (a.ayrinti ->> 'sure_ms')::numeric)::numeric,
         round(avg(case when coalesce((a.ayrinti ->> 'ipucu')::numeric, 0) > 0 then 1 else 0 end), 3),
         percentile_cont(0.5) within group (order by a.puan)::numeric,
         percentile_cont(0.5) within group (order by (a.ayrinti ->> 'lt')::numeric)::numeric
  from sezgi.attempts a join sezgi.daily_puzzles p on p.id = a.puzzle_id
  where a.status = 'submitted' and a.submitted_at >= p_bas and a.submitted_at < p_bit
    and a.ayrinti is not null and a.flags = '{}'
  group by p.kind, p.game, p.day, a.puan_surumu
  order by p.day, p.kind, p.game
$$;
revoke execute on function sezgi.kalibrasyon(timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function sezgi.kalibrasyon(timestamptz, timestamptz) to service_role;
