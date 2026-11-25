-- Göç 8320: Beat Greedy önizleme reddi (BG oturumunun isteği, 23 Kasım; docs/ONIZLEME.md). BG'nin kendi SQL yolları
-- (start_attempt_tx: Keşif ve Yarış, lig kurma tetikleyicisi, join_league) önizlemede testçi olmayana kapalı. Kapalılık
-- ortak.etkin_bayraklar('sezgi', kullanıcı)'dan okunur: elle kapatılan bölüm (kesif/yaris/lig) ya da önizlemenin kapattığı
-- özellik (gunluk → kesif ve yaris, lig → lig). Testçiye hiçbiri kapalı değildir.

create function sezgi.bolum_kapali(p_bolum text, p_kullanici uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  with b as (select coalesce(ortak.etkin_bayraklar('sezgi', p_kullanici) -> 'kapali', '[]'::jsonb) as k)
  select (b.k ? p_bolum) or (p_bolum in ('kesif', 'yaris') and b.k ? 'gunluk') from b
$$;
revoke all on function sezgi.bolum_kapali(text, uuid) from public, anon, authenticated;
grant execute on function sezgi.bolum_kapali(text, uuid) to service_role;

-- Tek bağımsız değişkenli sürüm (tetikleyici ve join_league çağırır) oturumdaki kullanıcıyla aynı işi yapar.
create or replace function sezgi.bolum_kapali(p_bolum text) returns boolean
language sql stable security definer set search_path = '' as $$
  select sezgi.bolum_kapali(p_bolum, auth.uid())
$$;

-- start_attempt_tx servis rolüyle çağrılır (auth.uid() boş): kullanıcı açıkça verilir. Gövdenin geri kalanı göç 7400 ile aynı.
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
     and bolum_kapali(case p.kind when 'race' then 'yaris' else 'kesif' end, p_user) then
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
