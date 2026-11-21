-- 20261120001200 düzeltmesi (güvenlik incelemesi, 15 Kasım 2026):
-- 1) "Tamamen sil" (ortak.hesabi_sil) kimlik özeti yazmadan giriş kaydını siliyordu; aynı gün yeniden açan sıralamaya
--    girebilirdi. Halka ve Beat Greedy hesabiSil()'e geçti, kullanan oyun kalmadı: istemci yetkisi kaldırıldı (OA-1'in
--    yarısı; hesap_ozeti Sticky geçince kapanır).
-- 2) Engel yalnız "bugün"e bakıyordu: dünün dönemine geç gönderilen skor (silmeden sonra) girebilirdi. Artık skorun
--    dönem gününün başından bu yana yapılmış silme sayılır.

revoke execute on function ortak.hesabi_sil() from authenticated;

create or replace function ortak.ayni_gun_siralama_engeli() returns trigger
language plpgsql security definer set search_path = '' as $$
declare bas timestamptz := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
begin
  if new.tur <> 'gunluk' then return new; end if;
  if new.donem ~ '^\d{4}-\d{2}-\d{2}$' then
    bas := least(bas, new.donem::date::timestamp at time zone 'Europe/Istanbul');
  end if;
  if not exists (select 1 from ortak.silinen_kimlikler where oyun_id = new.oyun_id and silindi >= bas) then return new; end if;
  if exists (select 1 from ortak.silinen_kimlikler
             where oyun_id = new.oyun_id and silindi >= bas and ozet = any (ortak.kimlik_ozetleri(new.kullanici_id))) then
    return null;
  end if;
  return new;
end $$;
