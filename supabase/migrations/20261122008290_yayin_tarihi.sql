-- Göç 8290: yayın tarihi (kurucu, 22 Kasım). Günlük ve etkinlik takvimi yayın tarihine göre kaydırılabilsin; önizleme günleri
-- kurucunun bakabileceği örnek olarak kalsın.
-- - ortak.oyunlar.ayarlar.yayin_tarihi: 'YYYY-AA-GG' ya da yok (henüz belli değil).
-- - etkin_bayraklar (ve acilis) herkese yayin_tarihi'ni de döner: oyun "Gün N" sayısını, arşivin başını ve etkinlik takvimini
--   buna göre hesaplar. Tarih değişince istemci güncellemesi gerekmez.
-- İçerik kaydırma ayrı bir şema gerektirmez: oyun günlük takvimini yayın tarihinden başlatıp yeniden yükler; yükleme kuralı
-- (acilmis_gun_koru) yalnız açılmamış gelecek günleri değiştirir, önizleme günleri örnek olarak kalır.

create or replace function ortak.etkin_bayraklar(p_oyun text, p_kullanici uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  with o as (
    select coalesce(ayarlar -> 'bayraklar', '{}'::jsonb)
             || case when ayarlar ? 'yayin_tarihi' then jsonb_build_object('yayin_tarihi', ayarlar -> 'yayin_tarihi') else '{}'::jsonb end as b,
           coalesce(ayarlar ->> 'yayin', 'acik') as y
      from ortak.oyunlar where id = p_oyun
  ), t as (
    select exists (select 1 from ortak.testciler where kullanici_id = p_kullanici) as testci
  )
  select case
    when o.y <> 'onizleme' then o.b
    when t.testci then o.b || '{"onizleme": true, "testci": true, "lig_acik": true}'::jsonb
    else o.b || jsonb_build_object('onizleme', true, 'kapali',
           (select coalesce(jsonb_agg(distinct k), '[]'::jsonb) from (
              select jsonb_array_elements_text(coalesce(o.b -> 'kapali', '[]'::jsonb)) as k
              union select unnest(array['gunluk', 'lig', 'etkinlik', 'siralama', 'duello'])) x))
  end
  from o, t;
$$;
