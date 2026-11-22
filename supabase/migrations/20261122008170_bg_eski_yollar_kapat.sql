-- Beat Greedy, 22 Kasım: göç 7400'ün "istemci geçince kapatılacak" dediği eski veri yolları kapanır. İstemci 21 Kasım'dan
-- beri canlıda yeni yollarda (sezgi 6e47d53: board_week_v/board_all_time_v, `ben`, league_members_v, *_uye RPC'leri).
-- Amaç: oyuncu başka oyuncunun user_id'sini hiçbir yoldan okuyamasın.
--
-- 1) league_members: tablo kapanmaz (hesap verisini dışa aktarma kendi satırlarını leagues ile okur); okuma yalnız kendi
--    satırları. Başka üyeler league_members_v'den (uye, user_id yok). Görünüm tablo sahibiyle okur, RLS'den etkilenmez.
-- 2) board_week ve board_all_time (materyalize) API'ye kapanır; okuma _v görünümlerinden. Görünümler, lig görünümleri ve
--    refresh_boards sahibin (postgres) yetkisiyle okur.
-- 3) Tablo görünümlerinde user_id oturum açmış oyuncuya da kapanır (misafire BG-12'den beri kapalı): sütun düzeyinde yetki.
--    Sütun silinmez; sunucu tarafı user_id ile okumaya devam eder: submit_attempt Edge Function (service_role,
--    board_day?user_id=eq.), materyalize board_week/board_all_time (board_day'den türer), my_daily_stats (security definer).
--    Dikkat: bu görünümlere create or replace ile yeni sütun eklenirse authenticated'a o sütun ayrıca verilmeli.
--    board_levels'a `ben` eklenir (istemci girişliyken ister; yoktu, İlerleme tablosu hata veriyordu).
-- 4) user_id alan eski transfer_league / remove_league_member istemciye kapanır; *_uye işlevleri (security definer) bunları
--    sahibin yetkisiyle çağırır.
-- 5) game_sign sabit search_path alır.
-- Yapılmayan: leagues.owner_id okuması açık kalır (istemci kendi liglerini owner_id = kendi kimliği süzgeciyle bulur,
-- privacy.ts fetchOwnedLeagues). yeni_puan anon/authenticated'dan alınmaz: tablo görünümleri onu çağırır ve görünümde
-- çağrılan işlevin yetkisi okuyanınkiyle denetlenir; alınırsa bütün tablolar "permission denied" verir.

-- ---------------------------------------------------------------- 1) league_members: yalnız kendi satırı
drop policy league_members_read on sezgi.league_members;
create policy league_members_kendi on sezgi.league_members for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------- 2) materyalize tablolar API dışı
revoke select on sezgi.board_week, sezgi.board_all_time from anon, authenticated;

-- ---------------------------------------------------------------- 3) board_levels'a ben; görünümlerde user_id kapalı
create or replace view sezgi.board_levels as
with t as (
  select level_verified.user_id, coalesce(level_verified.game, 'all') as game,
         sum(level_verified.raw_stars)::int as stars,
         count(*) filter (where level_verified.puan >= 100)::int as master3,
         max(level_verified.verified_at) as reached_at,
         sum(level_verified.puan) as puan
  from sezgi.level_verified
  where level_verified.level < 4000
  group by grouping sets ((level_verified.user_id, level_verified.game), (level_verified.user_id))
)
select t.game, t.user_id, pr.username, pr.avatar, t.stars, t.master3, t.reached_at,
       rank() over (partition by t.game
         order by case when sezgi.yeni_puan(sezgi.istanbul_today()) then t.puan else t.stars::numeric end desc nulls last,
                  case when sezgi.yeni_puan(sezgi.istanbul_today()) then t.master3 else 0 end desc,
                  t.reached_at) as rank,
       t.puan,
       t.user_id = (select auth.uid()) as ben
from t
join sezgi.profiles pr on pr.id = t.user_id
where t.stars > 0 or t.puan > 0;

do $$
declare
  v text;
  sutunlar text;
begin
  foreach v in array array['board_game_day', 'board_day', 'board_race', 'board_race_day', 'board_levels',
                           'league_board_game_day', 'league_board_day', 'league_board_week', 'league_board_all_time'] loop
    select string_agg(quote_ident(attname), ', ' order by attnum) into sutunlar
    from pg_attribute
    where attrelid = format('sezgi.%I', v)::regclass and attnum > 0 and not attisdropped and attname <> 'user_id';
    execute format('revoke select on sezgi.%I from authenticated', v);
    execute format('grant select (%s) on sezgi.%I to authenticated', sutunlar, v);
  end loop;
end $$;

-- ---------------------------------------------------------------- 4) eski user_id'li lig işlevleri
revoke execute on function sezgi.transfer_league(uuid, uuid), sezgi.remove_league_member(uuid, uuid)
  from public, anon, authenticated;
grant execute on function sezgi.transfer_league(uuid, uuid), sezgi.remove_league_member(uuid, uuid) to service_role;

-- ---------------------------------------------------------------- 5) game_sign
alter function sezgi.game_sign(text) set search_path = '';
