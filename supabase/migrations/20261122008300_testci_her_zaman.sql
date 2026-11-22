-- Göç 8300: testçi yayından sonra da testçi (kurucu, 22 Kasım: "test hesabıma hepsi her an açık"). 8290'da yayın 'acik'
-- olunca testci bayrağı dönmüyordu; oyun bütün seviyeleri testci ile açtığı için kurucu yayından sonra ücretli kısmı
-- kaybederdi. Artık testçiye her zaman testci: true döner; önizleme bayrağı yalnız önizlemede.

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
    when o.y <> 'onizleme' and t.testci then o.b || '{"testci": true}'::jsonb
    when o.y <> 'onizleme' then o.b
    when t.testci then o.b || '{"onizleme": true, "testci": true, "lig_acik": true}'::jsonb
    else o.b || jsonb_build_object('onizleme', true, 'kapali',
           (select coalesce(jsonb_agg(distinct k), '[]'::jsonb) from (
              select jsonb_array_elements_text(coalesce(o.b -> 'kapali', '[]'::jsonb)) as k
              union select unnest(array['gunluk', 'lig', 'etkinlik', 'siralama', 'duello'])) x))
  end
  from o, t;
$$;
