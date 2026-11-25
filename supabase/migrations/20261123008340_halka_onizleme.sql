-- HK-24 (oyun-ortak 23 Kasım 2026, docs/ONIZLEME.md): önizlemede günlük ve etkinlik veritabanı yolundan da verilmez.
-- Göçü oyun-ortak uygular; 8280 (ortak.etkin_bayraklar) ve hk22'den (oyun-ortak 20261120004660) sonra. Yalnız public.halka_*
-- sarmalayıcıları ve iki yardımcı. Testi: halka-kelime tests/sql.test.ts "hk24". oyun-ortak göçü 8340 (23 Kasım).
--
-- Kural (dogrula-halka ile aynı, c.ozellikAcik): testçi olmayana önizlemede `kapali` içinde gunluk, etkinlik gelir.
--   - Bugünün kontrolü ve ipucu: `gunluk` kapalıysa 'kapali' hatası (elle kapatmada da).
--   - Etkinlik (Usta Turnuvası, tematik) dosyası, kontrolü, ipucu: `etkinlik` ya da eski elle kapatma adı `turnuva` kapalıysa.
--   - Arşiv (gün dosyası, takvim satırları, geçmiş günün cevabı): yalnız önizlemede kapalı (elle günlük kapatmada arşiv açık
--     kalır, istemci "Seviyeler ve arşiv açık" der). Okumalar boş döner: null / '[]'.
--   - Testçi örnekleri (`ornek-…`, src/ornek.ts): dosya, kontrol, ipucu yalnız testçiye; satırları upload_daily.ts yükler.
-- Oturumsuz (anon, auth.uid() boş) testçi değildir. Kenar (/api/kontrol) bileti dogrula-halka basla verir; basla da sorar.

create or replace function halka.ozellik_kapali(p_ozellik text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((ortak.etkin_bayraklar('halka', auth.uid()) -> 'kapali') ? p_ozellik, false)
$$;

create or replace function halka.onizlemede() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(b ->> 'onizleme' = 'true' and coalesce(b ->> 'testci', '') <> 'true', false)
    from (select ortak.etkin_bayraklar('halka', auth.uid()) as b) x
$$;
-- Testçi örnekleri (halka-kelime src/ornek.ts): `ornek-…` kimlikli etkinlik bulmacaları yalnız testçiye (yayından sonra da).
create or replace function halka.ornek_kapali(p_kimlik text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_kimlik like 'ornek-%' and coalesce(ortak.etkin_bayraklar('halka', auth.uid()) ->> 'testci', '') <> 'true'
$$;
revoke all on function halka.ozellik_kapali(text), halka.onizlemede(), halka.ornek_kapali(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- arşiv ve dosyalar (hk22 gövdeleri + önizleme)
create or replace function public.halka_gunluk_dosya(p_tarih date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select g.dosya from halka.gunluk_bulmacalar g where g.tarih = p_tarih and g.tarih <= ortak.bugun() and not halka.onizlemede()
$$;

create or replace function public.halka_gunluk_dizin() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(g.dizin order by g.tarih), '[]'::jsonb)
    from halka.gunluk_bulmacalar g where g.tarih <= ortak.bugun() and g.dizin is not null and not halka.onizlemede()
$$;

create or replace function public.halka_turnuva_dosya(p_kimlik text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select t.dosya from halka.turnuva_bulmacalar t
   where t.kimlik = p_kimlik and t.basla <= ortak.bugun() and not halka.ozellik_kapali('etkinlik') and not halka.ozellik_kapali('turnuva')
     and not halka.ornek_kapali(p_kimlik)
$$;

create or replace function public.halka_gunluk_cevap(p_tarih date) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if halka.onizlemede() then return null; end if;
  return halka.gunluk_cevap(p_tarih);
end $$;

-- ---------------------------------------------------------------- bugünün ve etkinliğin kontrolü, ipucu
create or replace function public.halka_gunluk_kontrol(p_tarih date, p_rot integer[], p_flip boolean[]) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if halka.ozellik_kapali('gunluk') then raise exception 'kapali'; end if;
  return halka.gunluk_kontrol(p_tarih, p_rot, p_flip);
end $$;

create or replace function public.halka_gunluk_ipucu(p_tarih date, p_tur text, p_sira integer, p_rot integer[] default null,
                                                     p_flip boolean[] default null, p_kilitli integer[] default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if halka.ozellik_kapali('gunluk') then raise exception 'kapali'; end if;
  return halka.gunluk_ipucu(p_tarih, p_tur, p_sira, p_rot, p_flip, p_kilitli);
end $$;

create or replace function public.halka_turnuva_kontrol(p_kimlik text, p_rot integer[], p_flip boolean[]) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if halka.ozellik_kapali('etkinlik') or halka.ozellik_kapali('turnuva') or halka.ornek_kapali(p_kimlik) then raise exception 'kapali'; end if;
  return halka.turnuva_kontrol(p_kimlik, p_rot, p_flip);
end $$;

create or replace function public.halka_turnuva_ipucu(p_kimlik text, p_tur text, p_sira integer, p_rot integer[] default null,
                                                      p_flip boolean[] default null, p_kilitli integer[] default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if halka.ozellik_kapali('etkinlik') or halka.ozellik_kapali('turnuva') or halka.ornek_kapali(p_kimlik) then raise exception 'kapali'; end if;
  return halka.turnuva_ipucu(p_kimlik, p_tur, p_sira, p_rot, p_flip, p_kilitli);
end $$;
