-- Göç 8260: arkadaş listesinden düello açma (Koz isteği, 22 Kasım). Arayüz arkadaşın kodunu bilmez, yalnız tutamacını
-- (8230) bilir. koz_duello_ac'ın gövdesi iç işleve taşındı; kodla ve tutamaçla açan iki giriş aynı kuralları paylaşır
-- (arkadas_degil, havuz_bitti, gunluk_sinir, kullanıcı kilidi).

create function koz.duello_ac_ic(u uuid, r uuid, p_el int) returns uuid language plpgsql security definer set search_path = '' as $$
declare secim text[]; yeni uuid;
  gun_bas timestamptz := (ortak.bugun())::timestamp at time zone 'Europe/Istanbul';
begin
  if p_el not in (3, 5) then raise exception 'el_sayisi' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('koz-duello:' || u));
  if r is null or not exists (select 1 from koz.arkadaslik where kullanici = u and arkadas = r) then
    raise exception 'arkadas_degil' using errcode = '42501';
  end if;
  if (select count(*) from koz.duello where acan = u and olusturma >= gun_bas) >= 3 then
    raise exception 'gunluk_sinir' using errcode = '54000';
  end if;
  select array_agg(id) into secim from (
    select h.id from koz.duello_havuz h
    where not exists (select 1 from koz.duello d where (d.acan in (u, r) or d.rakip in (u, r)) and h.id = any(d.eller))
    order by random() limit p_el) x;
  if coalesce(cardinality(secim), 0) < p_el then raise exception 'havuz_bitti' using errcode = 'P0001'; end if;
  insert into koz.duello (acan, rakip, eller) values (u, r, secim) returning id into yeni;
  return yeni;
end $$;
revoke all on function koz.duello_ac_ic(uuid, uuid, int) from public, anon, authenticated;

create or replace function public.koz_duello_ac(p_kod text, p_el int) returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim();
begin
  return koz.duello_ac_ic(u, (select kullanici from koz.arkadas_kodu where kod = upper(trim(p_kod))), p_el);
end $$;

create function public.koz_duello_ac_tutamac(p_tutamac uuid, p_el int) returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim();
begin
  return koz.duello_ac_ic(u, (select arkadas from koz.arkadaslik where kullanici = u and tutamac = p_tutamac), p_el);
end $$;
revoke all on function public.koz_duello_ac_tutamac(uuid, int) from public, anon;
grant execute on function public.koz_duello_ac_tutamac(uuid, int) to authenticated;
