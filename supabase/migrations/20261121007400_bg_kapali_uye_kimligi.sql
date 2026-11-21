-- Beat Greedy, 21 Kasım (BG oturumu kararlarıyla):
-- 1) O23 sunucu reddi: ortak.oyunlar('sezgi').ayarlar.bayraklar.kapali içinde 'kesif' (kind daily), 'yaris' (kind race)
--    ya da 'lig' varsa: yeni deneme açılmaz (start_attempt_tx {'error':'kapali'}; Edge Function 403 {"error":"kapali"}
--    döner), yeni lig kurulamaz (leagues INSERT 'kapali'), lige katılınamaz (join_league 'kapali'). Başlamış deneme
--    sürdürülebilir; teslim, nabız, ayrılma, çıkarma, devir, kod yenileme ve okuma açık kalır.
-- 2) Haftalık ve tüm zamanlar tabloları için user_id yerine `ben` taşıyan görünümler: board_week_v, board_all_time_v.
--    İstemci geçince materyalize görünümler API'den kapatılacak (ayrı göç).
-- 3) Lig üyeleri birbirinin user_id'sini görmesin: league_members'a kalıcı üye kimliği (uye), okuma için
--    league_members_v (uye, rol, ad, ben), devir ve çıkarma için uye alan transfer_league_uye / remove_league_uye.
--    Geçişte eski user_id'li işlevler ve tablo okuması açık kalır; istemci geçince kapatılacak.

create function sezgi.bolum_kapali(p_bolum text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select (o.ayarlar -> 'bayraklar' -> 'kapali') ? p_bolum from ortak.oyunlar o where o.id = 'sezgi'), false)
$$;
revoke all on function sezgi.bolum_kapali(text) from public, anon, authenticated;
grant execute on function sezgi.bolum_kapali(text) to service_role;

create or replace function sezgi.start_attempt_tx(
  p_user uuid, p_game text, p_engine_version int, p_client_version int, p_kind text
) returns jsonb language plpgsql set search_path = sezgi set extra_float_digits = 1 as $$
declare
  p daily_puzzles;
  a attempts;
begin
  select * into p from daily_puzzles where kind = p_kind and game = p_game and day = istanbul_today();
  if not found then return jsonb_build_object('error', 'no_puzzle'); end if;
  if p.engine_version <> p_engine_version then return jsonb_build_object('error', 'engine_mismatch'); end if;
  if p.engine_version <> coalesce(p_client_version, p.engine_version) then
    return jsonb_build_object('error', 'client_outdated');
  end if;
  if not exists (select from profiles where id = p_user) then
    return jsonb_build_object('error', 'no_profile');
  end if;
  -- O23: kapalı bölümde yalnız yeni deneme reddedilir; başlamış deneme sürdürülür.
  if not exists (select from attempts where user_id = p_user and puzzle_id = p.id)
     and bolum_kapali(case p.kind when 'race' then 'yaris' else 'kesif' end) then
    return jsonb_build_object('error', 'kapali');
  end if;
  perform expire_attempts();
  insert into attempts (user_id, puzzle_id, status) values (p_user, p.id, 'started')
  on conflict (user_id, puzzle_id) do nothing;
  select * into a from attempts where user_id = p_user and puzzle_id = p.id;
  return jsonb_build_object(
    'attempt_id', a.id, 'puzzle_id', p.id, 'kind', p.kind, 'game', p.game, 'day', p.day,
    'status', a.status, 'started_at', a.started_at, 'server_now', now(),
    'engine_version', p.engine_version, 'params', p.params, 'instance', p.instance,
    'target_value', case when p.kind = 'daily' and a.status = 'started' then null else p.target_value end,
    'target_proven', p.target_proven, 'baseline', p.baseline,
    'value', a.value, 'score', a.score, 'duration_ms', a.duration_ms, 'flags', a.flags,
    'hints', a.hints, 'reached', a.reached);
end $$;

create function sezgi.lig_kapali_denetle() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if sezgi.bolum_kapali('lig') then raise exception 'kapali' using errcode = 'P0001'; end if;
  return new;
end $$;
revoke all on function sezgi.lig_kapali_denetle() from public, anon, authenticated;
create trigger lig_kapali before insert on sezgi.leagues for each row execute function sezgi.lig_kapali_denetle();

create or replace function sezgi.join_league(p_code text) returns uuid
language plpgsql security definer set search_path = sezgi as $$
declare
  l uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if not hit_rate_limit(auth.uid(), 'league_code', 20) then raise exception 'rate_limited'; end if;
  select id into l from leagues where invite_code = upper(btrim(p_code)) for update;
  if l is null then return null; end if;
  if exists (select from league_members where league_id = l and user_id = auth.uid()) then return l; end if;
  if bolum_kapali('lig') then raise exception 'kapali'; end if;
  perform 1 from profiles where id = auth.uid() for no key update;
  if (select count(*) from league_members where user_id = auth.uid()) >= 10 then raise exception 'league_limit'; end if;
  if (select count(*) from league_members where league_id = l) >= 100 then raise exception 'league_full'; end if;
  insert into league_members (league_id, user_id) values (l, auth.uid());
  return l;
end $$;

-- ---------------------------------------------------------------- haftalık ve tüm zamanlar (ben)
create view sezgi.board_week_v as
select b.week_start, b.username, b.avatar, b.total, b.total_ms, b.days, b.rank, b.puan, b.ikincil,
       b.user_id = (select auth.uid()) as ben
from sezgi.board_week b;

create view sezgi.board_all_time_v as
select b.username, b.avatar, b.total, b.total_ms, b.days, b.rank, b.puan, b.ikincil,
       b.user_id = (select auth.uid()) as ben
from sezgi.board_all_time b;

revoke all on sezgi.board_week_v, sezgi.board_all_time_v from public, anon, authenticated;
grant select on sezgi.board_week_v, sezgi.board_all_time_v to anon, authenticated;
grant all on sezgi.board_week_v, sezgi.board_all_time_v to service_role;

-- ---------------------------------------------------------------- lig üye kimliği
alter table sezgi.league_members add column uye uuid not null default gen_random_uuid();
create unique index league_members_uye on sezgi.league_members (uye);

-- Yalnız çağıranın üye olduğu liglerin üyeleri; user_id yok.
create view sezgi.league_members_v as
select m.league_id, m.uye, m.role, m.joined_at, pr.username, pr.avatar,
       m.user_id = (select auth.uid()) as ben
from sezgi.league_members m
join sezgi.profiles pr on pr.id = m.user_id
where sezgi.is_league_member(m.league_id);
revoke all on sezgi.league_members_v from public, anon, authenticated;
grant select on sezgi.league_members_v to authenticated;
grant all on sezgi.league_members_v to service_role;

create function sezgi.transfer_league_uye(p_league uuid, p_uye uuid) returns void
language plpgsql security definer set search_path = sezgi as $$
declare u uuid;
begin
  select user_id into u from league_members where league_id = p_league and uye = p_uye;
  if u is null then raise exception 'not_member'; end if;
  perform transfer_league(p_league, u);
end $$;

create function sezgi.remove_league_uye(p_league uuid, p_uye uuid) returns void
language plpgsql security definer set search_path = sezgi as $$
declare u uuid;
begin
  select user_id into u from league_members where league_id = p_league and uye = p_uye;
  if u is null then raise exception 'not_member'; end if;
  perform remove_league_member(p_league, u);
end $$;

revoke all on function sezgi.transfer_league_uye(uuid, uuid), sezgi.remove_league_uye(uuid, uuid) from public, anon, authenticated;
grant execute on function sezgi.transfer_league_uye(uuid, uuid), sezgi.remove_league_uye(uuid, uuid) to authenticated, service_role;
