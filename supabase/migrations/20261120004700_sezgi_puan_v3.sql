-- Beat Greedy puan sürüm 3 (ADIL_PUAN §1.1, §1.7; kurucu 17 Kasım 2026; sezgi docs/PUAN_V3.md). Kapı Pazartesi
-- 2026-11-23: motorun POINTS_V3_FROM'u ile aynı gün. Keşif ve Yarış puanı en çok 110 (hız ödülü); sunucuda bunlara
-- 100 sınırı yok, değişiklik gerekmiyor. Seviye puanı en çok 100 kalır. Sürüm 3 gününde seviyenin ilk kaydı kalıcıdır,
-- puanı ne olursa olsun (geçmese de); tekrar oynamak alıştırmadır. Lig rozet eşikleri (+%10) istemcide. Kapıdan
-- önceki skorlar yeniden hesaplanmaz (§3.2).

create table sezgi.puan_surumleri (
  formul int primary key check (formul > 0),
  gecerli date not null check (extract(isodow from gecerli) = 1)
);
alter table sezgi.puan_surumleri enable row level security;
revoke all on sezgi.puan_surumleri from public, anon, authenticated;
insert into sezgi.puan_surumleri values (3, '2026-11-23');

create function sezgi.puan_v3(p_gun date) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from sezgi.puan_surumleri where formul = 3 and gecerli <= p_gun)
$$;
grant execute on function sezgi.puan_v3(date) to anon, authenticated, service_role;

-- 20261120003400 sürümü + sürüm 3 gününde var olan satır hiç değişmez (ilk kayıt kalıcı).
create or replace function sezgi.record_level(
  p_user uuid, p_game text, p_level int, p_raw_stars int, p_value double precision, p_puan numeric default null
) returns jsonb language plpgsql set search_path = sezgi set extra_float_digits = 1 as $$
declare
  r level_verified;
  v3 boolean := sezgi.puan_v3(sezgi.istanbul_today());
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
    where not v3 and (excluded.raw_stars > v.raw_stars or excluded.puan > coalesce(v.puan, -1));
  select * into r from level_verified where user_id = p_user and game = p_game and level = p_level;
  return jsonb_build_object('game', r.game, 'level', r.level, 'raw_stars', r.raw_stars,
    'value', r.value, 'puan', r.puan, 'verified_at', r.verified_at);
end $$;
