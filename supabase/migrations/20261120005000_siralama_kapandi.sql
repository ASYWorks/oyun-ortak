-- Sıralama yanıtına `kapandi` (Halka isteği, kurucu 18 Kasım; Usta Turnuvası "Sonuçlar hazırlanıyor" / "Kesin sonuç").
-- true: bu dönem için sıra ödülü yazılmış (ortak.siralama_odulu_ver, kaynak = tur:donem, ödül `sira:` önekli);
-- kapanış işi çalıştı, sıra artık değişmez. Ödül işi olmayan tür ve dönemlerde (günlük gibi) false. Başka değişiklik yok.
create or replace function ortak.siralama(p_oyun text, p_tur text, p_donem text, p_ilk integer default 10, p_cevre integer default 3)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  a jsonb;
  esik int;
  ben uuid := auth.uid();
  r jsonb;
begin
  select coalesce(ayarlar -> 'siralama', '{}') into a from ortak.oyunlar where id = p_oyun;
  if not found then raise exception 'oyun_yok'; end if;
  esik := coalesce((a ->> 'dagilim_esigi')::int, 50);
  p_ilk := least(greatest(p_ilk, 1), 100);
  p_cevre := least(greatest(p_cevre, 0), 10);

  with s as (select * from ortak.sira_listesi(p_oyun, p_tur, p_donem)),
  t as (select count(*)::int as c from s),
  b as (select sn, sira from s where s.kullanici_id = ben)
  select jsonb_build_object(
    'toplam', t.c,
    'kapandi', exists (select 1 from ortak.oduller od where od.oyun_id = p_oyun
                         and od.kaynak = p_tur || ':' || p_donem and od.odul like 'sira:%'),
    'ben', (select jsonb_build_object('sira', b.sira,
              'ust_yuzde', case when t.c >= esik then ceil(100.0 * b.sira / t.c) end) from b),
    'satirlar', coalesce((
      select jsonb_agg(jsonb_build_object('sira', s.sira, 'ad', o.ad, 'puan', s.puan, 'ikincil', s.ikincil,
                                          'ben', coalesce(s.kullanici_id = ben, false)) order by s.sn)
      from s left join ortak.oyuncular o on o.oyun_id = p_oyun and o.kullanici_id = s.kullanici_id
      where s.sn <= p_ilk or exists (select 1 from b where abs(s.sn - b.sn) <= p_cevre)), '[]'::jsonb))
  into r from t;
  return r;
end $$;
