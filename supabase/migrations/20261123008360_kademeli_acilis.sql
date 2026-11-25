-- Göç 8360: kademeli açılış ve turnuva (kurucu, 23 Kasım).
-- 1. Önizleme yapısı ilk yayında da kullanılır: yayından sonra `ayarlar.bayraklar.kapali` henüz açılmamış özellikleri
--    (günlük, etkinlik, lig...) tutar; oyuncu sayısı arttıkça kurucu kararıyla listeden çıkarılır. Testçi bu listeye
--    takılmaz: 8300'de yayından sonra testçiye `kapali` da dönüyordu, kademeli açılışta kurucu kapalı özelliği deneyemezdi.
-- 2. Önizlemede sıralamaya giren her şey kapalı: listeye `turnuva` eklendi (Halka turnuvası, ileride başka oyunlar).
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
    when o.y <> 'onizleme' and t.testci then (o.b - 'kapali') || '{"testci": true}'::jsonb
    when o.y <> 'onizleme' then o.b
    when t.testci then (o.b - 'kapali') || '{"onizleme": true, "testci": true, "lig_acik": true}'::jsonb
    else o.b || jsonb_build_object('onizleme', true, 'kapali',
           (select coalesce(jsonb_agg(distinct k), '[]'::jsonb) from (
              select jsonb_array_elements_text(coalesce(o.b -> 'kapali', '[]'::jsonb)) as k
              union select unnest(array['gunluk', 'lig', 'etkinlik', 'turnuva', 'siralama', 'duello'])) x))
  end
  from o, t;
$$;
