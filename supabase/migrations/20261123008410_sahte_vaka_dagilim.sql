-- Göç 8410 (SM-5, kurucu onayı 22 Kasım): Sahte Masası vaka bazında karar dağılımı. Bölümün açıklama ekranında "oyuncuların
-- yüzde X'i bu vakada doğru karar verdi" satırı için. Geçmiş bir günün (gün < bugün, İstanbul) bitmiş günlük denemelerinden
-- (ortak.denemeler, anahtar gunluk:<gun>, durum.kararlar[] = {vaka, secim}) her vaka için seçim sayıları. Doğru oranını istemci
-- doğru kararla hesaplar. Kişisel veri dönmez. Bugün ve sonrası için boş (cevap sızmasın); 20'den az bitmiş deneme varsa boş.
-- Herkese açık; IP başına dakikada 60 çağrı (sayaç yazdığı için volatile).

create function public.sahte_vaka_dagilim(p_gun date) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
begin
  if not ortak.hiz_siniri('sahte_dagilim:' || coalesce(current_setting('request.headers', true)::jsonb ->> 'cf-connecting-ip', 'yerel'), 60, 60) then
    raise exception 'cok_istek' using errcode = '54000';
  end if;
  if p_gun is null or p_gun >= ortak.bugun() then return '[]'::jsonb; end if;
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

revoke all on function public.sahte_vaka_dagilim(date) from public;
grant execute on function public.sahte_vaka_dagilim(date) to anon, authenticated, service_role;
