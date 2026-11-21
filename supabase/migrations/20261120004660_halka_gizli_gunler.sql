-- Kaynak: halka-kelime supabase/hk22_gizli_gunler.sql (c87a50e, inceleme-2), testi halka-kelime tests/sql.test.ts "hk22".
-- HK-22 (kurucu 17 Kasım 2026, ölçek ve iyi örnekler incelemesi): gelecek günlerin bulmacası istemciye verilmez.
-- Önceden yıllık günlük dosyaları (cevapsız ama halkalarıyla) ve Usta Turnuvası dosyaları sitede herkese açıktı: yarının
-- bulmacası bugünden çözülüp gece yarısı sıralamaya girilebilirdi. Artık istemci dosyası (eskiden public/puzzles/<gün>.json,
-- etkinlik/usta-*.json) ve takvim satırı (puzzles/index.json) sunucuda; okuma işlevleri yalnız açılmış günü verir.
-- Önce hk21_puan.sql. Uygulama oyun-ortak oturumunda (göç), ardından scripts/upload_daily.ts dosya sütunlarını doldurur.

alter table halka.gunluk_bulmacalar add column if not exists dosya jsonb;   -- istemci dosyası (cevapsız): { kind, puzzle, … }
alter table halka.gunluk_bulmacalar add column if not exists dizin jsonb;   -- takvim satırı: { date, number, tier, kind, theme, rings, rays }
alter table halka.turnuva_bulmacalar add column if not exists dosya jsonb;  -- istemci dosyası (cevapsız): { kind, puzzle }

-- Yükleme (yalnız servis rolü): var olan satırlara dosya ve takvim satırı yazılır (bulmaca verisi halka_*_yukle ile).
create or replace function public.halka_dosya_yukle(p_gunler jsonb, p_turnuvalar jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare n int; m int;
begin
  update halka.gunluk_bulmacalar g set dosya = x.dosya, dizin = x.dizin
    from jsonb_to_recordset(coalesce(p_gunler, '[]')) as x(tarih date, dosya jsonb, dizin jsonb)
   where g.tarih = x.tarih;
  get diagnostics n = row_count;
  update halka.turnuva_bulmacalar t set dosya = x.dosya
    from jsonb_to_recordset(coalesce(p_turnuvalar, '[]')) as x(kimlik text, dosya jsonb)
   where t.kimlik = x.kimlik;
  get diagnostics m = row_count;
  return n + m;
end $$;

-- Okuma (misafir dahil, oturum gerekmez): yalnız açılmış gün (İstanbul takvim günü, ortak.bugun()) ve başlamış turnuva.
create or replace function public.halka_gunluk_dosya(p_tarih date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select g.dosya from halka.gunluk_bulmacalar g where g.tarih = p_tarih and g.tarih <= ortak.bugun()
$$;

create or replace function public.halka_gunluk_dizin() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(g.dizin order by g.tarih), '[]'::jsonb)
    from halka.gunluk_bulmacalar g where g.tarih <= ortak.bugun() and g.dizin is not null
$$;

create or replace function public.halka_turnuva_dosya(p_kimlik text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select t.dosya from halka.turnuva_bulmacalar t where t.kimlik = p_kimlik and t.basla <= ortak.bugun()
$$;

revoke execute on function public.halka_dosya_yukle(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.halka_dosya_yukle(jsonb, jsonb) to service_role;
revoke execute on function public.halka_gunluk_dosya(date), public.halka_gunluk_dizin(), public.halka_turnuva_dosya(text) from public;
grant execute on function public.halka_gunluk_dosya(date), public.halka_gunluk_dizin(), public.halka_turnuva_dosya(text)
  to anon, authenticated, service_role;
