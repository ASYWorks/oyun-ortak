-- Güvenlik kontrolü (19 Kasım): sticky.siralama girişsiz de açık, her çağrıda dönemin bütün puan kaydını topluyor ve hız
-- sınırı yoktu (ortak.siralama ile aynı açık, 5800). Dakikada 120; Sticky sunucusu servis rolüyle sınırsız. İşlev artık stable değil.

create or replace function sticky.siralama(p_donem text, p_ilk int default 100, p_baslangic timestamptz default null,
                                p_kullanici uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  bas timestamptz := coalesce(p_baslangic, sticky.donem_baslangici(p_donem));
  en_az int := case p_donem when 'gun' then 3 when 'hafta' then 5 when 'ay' then 10 else 10 end;
  -- ST-7: servis rolü (Sticky sunucusu) oyuncunun kimliğini verir; başka çağıranda p_kullanici yok sayılır.
  ben uuid := coalesce(case when auth.role() = 'service_role' then p_kullanici end, auth.uid());
  r jsonb;
  h json := nullif(current_setting('request.headers', true), '')::json;
begin
  -- Dakikada 120 (girişliye kimlikle, girişsize IP ile; Sticky sunucusu servis rolüyle sınırsız). Her çağrı dönemin bütün
  -- puan kaydını toplar ve sıralar.
  if auth.role() is distinct from 'service_role' and not ortak.hiz_siniri('sticky-siralama:' || coalesce(auth.uid()::text,
       h ->> 'cf-connecting-ip', split_part(h ->> 'x-forwarded-for', ',', 1), 'anon'), 120, 60) then
    raise exception 'cok_istek' using errcode = '54000';
  end if;
  if p_donem not in ('gun', 'hafta', 'ay', 'tum') then raise exception 'donem_gecersiz'; end if;
  p_ilk := least(greatest(p_ilk, 1), 500);
  with s as (
    select x.user_id, x.deger, x.oyun, o.ad
    from (
      select st.user_id, st.rating::numeric as deger, st.rated_games as oyun
      from sticky.stats st where p_donem = 'tum' and st.rated_games >= en_az
      union all
      select l.user_id, sum(l.delta)::numeric, count(*)::int
      from sticky.rating_log l where p_donem <> 'tum' and l.at >= bas
      group by l.user_id having count(*) >= en_az
    ) x
    join ortak.oyuncular o on o.oyun_id = 'sticky' and o.kullanici_id = x.user_id and o.ad is not null
  ),
  sirali as (select s.*, row_number() over (order by deger desc, oyun desc, ad asc) as sira from s)
  select jsonb_build_object(
    'toplam', (select count(*) from sirali),
    'ben', (select jsonb_build_object('sira', sira, 'deger', deger, 'oyun', oyun) from sirali where user_id = ben),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_object('sira', sira, 'ad', ad, 'deger', deger, 'oyun', oyun,
                                                              'ben', coalesce(user_id = ben, false)) order by sira)
                          from sirali where sira <= p_ilk), '[]'::jsonb))
  into r;
  return r;
end $$;
