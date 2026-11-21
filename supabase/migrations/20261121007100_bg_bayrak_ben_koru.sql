-- Beat Greedy, 21 Kasım (BG oturumu bulguları, kurucunun 19–20 Kasım güvenlik kararları):
-- 1) Nabız boşluğu bayraklı deneme (göç 5600, finish_attempt_tx) tablo görünümlerinden çıkar: Şampiyon tablosu, haftalık ve
--    tüm zamanlar (board_day'den türer) ve lig toplamı (submit_attempt gun_toplami_yaz board_day'i okur). Oyuncunun kendi sonucu
--    (attempts) değişmez. Halka'daki "Şampiyon ve lig dışı" kuralıyla aynı.
-- 2) Görünümlere `ben` (satır oturumdaki oyuncunun mu): istemci kendi satırını user_id karşılaştırmadan bulur; istemci geçince
--    user_id görünümlerden kaldırılacak (ayrı göç). board_week ve board_all_time materyalize (auth.uid() olamaz): onlar için
--    sarmalayıcı görünüm user_id kaldırılırken yazılır.
-- 3) Açılmış günün bulmacası sessizce değiştirilemez (sezgi.gecmis_bulmaca_koru, Halka göç 6800 ile aynı kural): oyun, gün,
--    motor, parametre, örnek, açgözlü değer ve taban değişirse ya da satır silinirse ret. Hedef sütunları (target_value,
--    target_proven, target_beaten, target_updated_at) serbest: update_beaten_targets geçmiş günün hedefini oyuncu aşınca günceller.
--    Bilinçli düzeltme: aynı oturumda `set sezgi.duzeltme = 'evet'`.
-- Yeni sütun yalnız sona eklendiği için create or replace yeterli; bağımlı materyalize görünümler korunur.

create or replace view sezgi.board_game_day as
select p.game, p.day, a.user_id, pr.username, pr.avatar, case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.score end as score, a.duration_ms, a.submitted_at,
       rank() over (partition by a.puzzle_id
         order by round((a.value * sezgi.game_sign(p.game))::numeric, 6) desc nulls last,
                  a.duration_ms asc, a.submitted_at asc) as rank,
       case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.value end as value,
       case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.puan end as puan,
       a.user_id = (select auth.uid()) as ben
from sezgi.attempts a
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where p.kind = 'daily' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags)) and not ('nabiz_boslugu' = any (a.flags));

create or replace view sezgi.board_day as
select p.day, a.user_id, pr.username, pr.avatar,
       sum(a.score)::int as total, sum(a.duration_ms)::bigint as total_ms, count(*)::int as games,
       rank() over (partition by p.day
         order by case when sezgi.yeni_puan(p.day) then sum(a.puan) else sum(a.score) end desc nulls last,
                  case when sezgi.yeni_puan(p.day) then sum((a.ayrinti ->> 'lt')::numeric) else sum(a.duration_ms) end asc nulls last) as rank,
       sum(a.puan) as puan, sum((a.ayrinti ->> 'lt')::numeric) as ikincil,
       a.user_id = (select auth.uid()) as ben
from sezgi.attempts a
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where p.kind = 'daily' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags)) and not ('nabiz_boslugu' = any (a.flags))
group by p.day, a.user_id, pr.username, pr.avatar;

create or replace view sezgi.league_board_game_day as
select m.league_id, p.game, p.day, a.user_id, pr.username, pr.avatar, case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.score end as score, a.duration_ms, a.submitted_at,
       rank() over (partition by m.league_id, a.puzzle_id
         order by round((a.value * sezgi.game_sign(p.game))::numeric, 6) desc nulls last,
                  a.duration_ms asc, a.submitted_at asc) as rank,
       case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.value end as value,
       case when now() >= ((p.day + 1)::timestamp at time zone 'Europe/Istanbul') + interval '1 hour' or exists (select 1 from sezgi.attempts mine where mine.puzzle_id = a.puzzle_id and mine.user_id = auth.uid() and mine.status in ('submitted','timeout')) then a.puan end as puan,
       a.user_id = (select auth.uid()) as ben
from sezgi.league_members me
join sezgi.league_members m on m.league_id = me.league_id
join sezgi.attempts a on a.user_id = m.user_id
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where me.user_id = auth.uid() and p.kind = 'daily' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags)) and not ('nabiz_boslugu' = any (a.flags));

create or replace view sezgi.league_board_day as
select m.league_id, p.day, a.user_id, pr.username, pr.avatar,
       sum(a.score)::int as total, sum(a.duration_ms)::bigint as total_ms, count(*)::int as games,
       rank() over (partition by m.league_id, p.day
         order by case when sezgi.yeni_puan(p.day) then sum(a.puan) else sum(a.score) end desc nulls last,
                  case when sezgi.yeni_puan(p.day) then sum((a.ayrinti ->> 'lt')::numeric) else sum(a.duration_ms) end asc nulls last) as rank,
       sum(a.puan) as puan, sum((a.ayrinti ->> 'lt')::numeric) as ikincil,
       a.user_id = (select auth.uid()) as ben
from sezgi.league_members me
join sezgi.league_members m on m.league_id = me.league_id
join sezgi.attempts a on a.user_id = m.user_id
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where me.user_id = auth.uid() and p.kind = 'daily' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags)) and not ('nabiz_boslugu' = any (a.flags))
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
       a.puan, (a.ayrinti ->> 'lt')::numeric as ikincil,
       a.user_id = (select auth.uid()) as ben
from sezgi.attempts a
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where p.kind = 'race' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags)) and not ('nabiz_boslugu' = any (a.flags));

create or replace view sezgi.board_race_day as
select p.day, a.user_id, pr.username, pr.avatar,
       count(*) filter (where a.reached)::int as goals,
       sum(a.duration_ms::bigint + a.hints * 30000) filter (where a.reached) as race_ms,
       count(*)::int as games,
       rank() over (partition by p.day
         order by case when sezgi.yeni_puan(p.day) then sum(a.puan) else count(*) filter (where a.reached) end desc nulls last,
                  case when sezgi.yeni_puan(p.day) then sum((a.ayrinti ->> 'lt')::numeric)
                       else sum(a.duration_ms::bigint + a.hints * 30000) filter (where a.reached) end asc nulls last) as rank,
       sum(a.puan) as puan, sum((a.ayrinti ->> 'lt')::numeric) as ikincil,
       a.user_id = (select auth.uid()) as ben
from sezgi.attempts a
join sezgi.daily_puzzles p on p.id = a.puzzle_id
join sezgi.profiles pr on pr.id = a.user_id
where p.kind = 'race' and a.status in ('submitted','timeout') and not ('kurulum' = any (a.flags)) and not ('nabiz_boslugu' = any (a.flags))
group by p.day, a.user_id, pr.username, pr.avatar;

create or replace view sezgi.league_board_week as
select m.league_id, b.week_start, b.user_id, b.username, b.avatar, b.total, b.total_ms, b.days,
       rank() over (partition by m.league_id, b.week_start
         order by case when sezgi.yeni_puan(b.week_start) then b.puan else b.total end desc nulls last,
                  case when sezgi.yeni_puan(b.week_start) then b.ikincil else b.total_ms end asc nulls last) as rank,
       b.puan, b.ikincil,
       b.user_id = (select auth.uid()) as ben
from sezgi.league_members me
join sezgi.league_members m on m.league_id = me.league_id
join sezgi.board_week b on b.user_id = m.user_id
where me.user_id = auth.uid();

create or replace view sezgi.league_board_all_time as
select m.league_id, b.user_id, b.username, b.avatar, b.total, b.total_ms, b.days,
       rank() over (partition by m.league_id
         order by case when sezgi.yeni_puan(sezgi.istanbul_today()) then b.puan else b.total end desc nulls last,
                  case when sezgi.yeni_puan(sezgi.istanbul_today()) then b.ikincil else b.total_ms end asc nulls last) as rank,
       b.puan, b.ikincil,
       b.user_id = (select auth.uid()) as ben
from sezgi.league_members me
join sezgi.league_members m on m.league_id = me.league_id
join sezgi.board_all_time b on b.user_id = m.user_id
where me.user_id = auth.uid();

refresh materialized view sezgi.board_week;
refresh materialized view sezgi.board_all_time;

-- ---------------------------------------------------------------- açılmış gün koruması
create function sezgi.gecmis_bulmaca_koru() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.day <= ortak.bugun() and coalesce(current_setting('sezgi.duzeltme', true), '') <> 'evet'
     and (tg_op = 'DELETE'
          or (old.game, old.day, old.kind, old.engine_version, old.params, old.instance, old.greedy_value, old.baseline)
             is distinct from
             (new.game, new.day, new.kind, new.engine_version, new.params, new.instance, new.greedy_value, new.baseline)) then
    raise exception 'acilmis_bulmaca_degisemez' using errcode = 'P0001',
      hint = 'Bilinçli düzeltme: aynı oturumda set sezgi.duzeltme = ''evet'' (docs/ISLETIM.md §9).';
  end if;
  return coalesce(new, old);
end $$;
revoke execute on function sezgi.gecmis_bulmaca_koru() from public, anon, authenticated;
create trigger gecmis_bulmaca_koru before update or delete on sezgi.daily_puzzles for each row execute function sezgi.gecmis_bulmaca_koru();
