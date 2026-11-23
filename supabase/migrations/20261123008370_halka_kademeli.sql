-- Göç 8370: Halka hk25, kademeli açılış (kurucu 23 Kasım; ONIZLEME "Ek kurallar" 5–6, göç 8360 sonrası). Kaynak: halka-kelime
-- supabase/hk25_kademeli.sql (Halka oturumu yazdı, PGlite testi tests/sql.test.ts "hk25"). Günlük ve arşiv gunluk bayrağına,
-- Usta Turnuvası turnuva bayrağına, tematik ve haftalık etkinlik etkinlik bayrağına bağlanır; kapalı özellik hiç yokmuş gibi.

create or replace function halka.turnuva_ozelligi(p_kimlik text) returns text
language sql immutable set search_path = '' as $$
  select case when p_kimlik like 'usta-%' or p_kimlik like 'ornek-usta-%' then 'turnuva' else 'etkinlik' end
$$;
revoke all on function halka.turnuva_ozelligi(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- günlük ve arşiv: gunluk
create or replace function public.halka_gunluk_dosya(p_tarih date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select g.dosya from halka.gunluk_bulmacalar g where g.tarih = p_tarih and g.tarih <= ortak.bugun() and not halka.ozellik_kapali('gunluk')
$$;

create or replace function public.halka_gunluk_dizin() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(g.dizin order by g.tarih), '[]'::jsonb)
    from halka.gunluk_bulmacalar g where g.tarih <= ortak.bugun() and g.dizin is not null and not halka.ozellik_kapali('gunluk')
$$;

create or replace function public.halka_gunluk_cevap(p_tarih date) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if halka.ozellik_kapali('gunluk') then return null; end if;
  return halka.gunluk_cevap(p_tarih);
end $$;

-- ---------------------------------------------------------------- etkinlik bulmacaları: turnuva ya da etkinlik
create or replace function public.halka_turnuva_dosya(p_kimlik text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select t.dosya from halka.turnuva_bulmacalar t
   where t.kimlik = p_kimlik and t.basla <= ortak.bugun()
     and not halka.ozellik_kapali(halka.turnuva_ozelligi(p_kimlik)) and not halka.ornek_kapali(p_kimlik)
$$;

create or replace function public.halka_turnuva_kontrol(p_kimlik text, p_rot integer[], p_flip boolean[]) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if halka.ozellik_kapali(halka.turnuva_ozelligi(p_kimlik)) or halka.ornek_kapali(p_kimlik) then raise exception 'kapali'; end if;
  return halka.turnuva_kontrol(p_kimlik, p_rot, p_flip);
end $$;

create or replace function public.halka_turnuva_ipucu(p_kimlik text, p_tur text, p_sira integer, p_rot integer[] default null,
                                                      p_flip boolean[] default null, p_kilitli integer[] default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if halka.ozellik_kapali(halka.turnuva_ozelligi(p_kimlik)) or halka.ornek_kapali(p_kimlik) then raise exception 'kapali'; end if;
  return halka.turnuva_ipucu(p_kimlik, p_tur, p_sira, p_rot, p_flip, p_kilitli);
end $$;
