-- Göç 8425: 8410'daki sahte_vaka_dagilim kapısı sahte_bolum ile aynı olur (güvenlik incelemesi, 23 Kasım). dogrula-sahte-masasi
-- dünün kararlarını gün kapandıktan sonra 3 saat daha kabul ediyor; "gün < bugün" kapısı o pencerede dünün dağılımını açıp
-- henüz bitirmemiş oyuncuya cevabı sızdırıyordu. Artık gün ancak sahte.bolum_acik ile açılınca (dün için 03:00'ten sonra) döner.
create or replace function public.sahte_vaka_dagilim(p_gun date) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
begin
  if not ortak.hiz_siniri('sahte_dagilim:' || coalesce(current_setting('request.headers', true)::jsonb ->> 'cf-connecting-ip', 'yerel'), 60, 60) then
    raise exception 'cok_istek' using errcode = '54000';
  end if;
  if p_gun is null or not sahte.bolum_acik(p_gun) then return '[]'::jsonb; end if;
  if (select count(*) from ortak.denemeler d
       where d.oyun_id = 'sahte' and d.anahtar = 'gunluk:' || p_gun and d.bitti) < 20 then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('vaka', x.vaka, 'sahte', x.sahte, 'gercek', x.gercek, 'dogrula', x.dogrula) order by x.vaka)
      from (select (k ->> 'vaka')::int as vaka,
                   count(*) filter (where k ->> 'secim' = 'sahte')::int as sahte,
                   count(*) filter (where k ->> 'secim' = 'gercek')::int as gercek,
                   count(*) filter (where k ->> 'secim' = 'dogrula')::int as dogrula
              from ortak.denemeler d, jsonb_array_elements(coalesce(d.durum -> 'kararlar', '[]'::jsonb)) k
             where d.oyun_id = 'sahte' and d.anahtar = 'gunluk:' || p_gun and d.bitti
               and jsonb_typeof(k -> 'vaka') = 'number'
             group by 1) x), '[]'::jsonb);
end $$;
