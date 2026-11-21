-- PU-3 kalibrasyon (ADIL_PUAN §3): hedef süre ve ipucu kaybı gerçek oyuncu verisinden haftalık ayarlanır.
-- Bulmaca (dönem) başına süre dağılımı, ipucu oranı ve türleri; yalnız servis rolü.
-- Kaynak ortak.skorlar.ayrinti: puan_surumu, sure (sn), ipuclari (tür listesi), zorluk, hedef_sure, puan_ham.
-- Bayraklı (şüpheli) skorlar dağılımı bozmasın diye dışarıda. ayrinti 90 gün tutulur.
-- Beat Greedy'nin verisi sezgi.attempts'te; onun görünümü PU-7 e ile gelir.
create function ortak.kalibrasyon(p_oyun text, p_bas timestamptz, p_bit timestamptz)
returns table (tur text, donem text, puan_surumu int, zorluk numeric, hedef_sure numeric, oyuncu bigint,
               sure_p10 numeric, sure_p25 numeric, sure_p50 numeric, sure_p75 numeric, sure_p90 numeric,
               ipucu_orani numeric, ipucu_turleri jsonb, puan_ham_p50 numeric)
language sql stable security definer set search_path = '' as $$
  with s as (
    select s.tur, s.donem, (s.ayrinti ->> 'puan_surumu')::int as surum, (s.ayrinti ->> 'zorluk')::numeric as zorluk,
           (s.ayrinti ->> 'hedef_sure')::numeric as hedef, (s.ayrinti ->> 'sure')::numeric as sure,
           (s.ayrinti ->> 'puan_ham')::numeric as ham, coalesce(s.ayrinti -> 'ipuclari', '[]') as ip
    from ortak.skorlar s
    where s.oyun_id = p_oyun and s.olusturma >= p_bas and s.olusturma < p_bit
      and s.ayrinti is not null and cardinality(s.bayraklar) = 0
  )
  select s.tur, s.donem, s.surum, max(s.zorluk), max(s.hedef), count(*),
         percentile_cont(0.1) within group (order by s.sure)::numeric,
         percentile_cont(0.25) within group (order by s.sure)::numeric,
         percentile_cont(0.5) within group (order by s.sure)::numeric,
         percentile_cont(0.75) within group (order by s.sure)::numeric,
         percentile_cont(0.9) within group (order by s.sure)::numeric,
         round(avg(case when jsonb_array_length(s.ip) > 0 then 1 else 0 end), 3),
         (select coalesce(jsonb_object_agg(t, n), '{}') from (
            select x as t, count(*) as n from s s2, jsonb_array_elements_text(s2.ip) x
            where s2.tur = s.tur and s2.donem = s.donem and s2.surum is not distinct from s.surum group by x) k),
         percentile_cont(0.5) within group (order by s.ham)::numeric
  from s group by s.tur, s.donem, s.surum
  order by s.tur, s.donem, s.surum
$$;
revoke execute on function ortak.kalibrasyon(text, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function ortak.kalibrasyon(text, timestamptz, timestamptz) to service_role;
