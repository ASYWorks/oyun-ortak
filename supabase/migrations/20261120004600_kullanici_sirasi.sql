-- Gönderim yanıtında sıra (Halka GC-3). Edge Function servis rolüyle bağlanır, orada auth.uid() yok; ortak.siralama
-- oyuncunun sırasını veremez. Sıralama kuralı tek yere (ortak.sira_listesi) alındı; ortak.siralama (istemci) ve
-- ortak.kullanici_sirasi (yalnız servis rolü) onu kullanır. ortak.siralama'nın davranışı aynı.

create function ortak.sira_listesi(p_oyun text, p_tur text, p_donem text)
returns table (kullanici_id uuid, puan numeric, ikincil numeric, sira bigint, sn bigint)
language sql stable security definer set search_path = '' as $$
  with a as (
    select case when x.a ->> 'yon' = 'artan' then -1 else 1 end as yon,
           coalesce(x.a ->> 'esitlik', 'ortak') = 'ikincil' as ikincilli
    from (select coalesce(ayarlar -> 'siralama', '{}') as a from ortak.oyunlar where id = p_oyun) x
  )
  select sk.kullanici_id, sk.puan, sk.ikincil,
    rank() over (order by sk.puan * a.yon desc, case when a.ikincilli then sk.ikincil end asc nulls last),
    row_number() over (order by sk.puan * a.yon desc, case when a.ikincilli then sk.ikincil end asc nulls last, sk.id)
  from ortak.skorlar sk, a
  where sk.oyun_id = p_oyun and sk.tur = p_tur and sk.donem = p_donem
$$;

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

-- Oyuncunun dönemdeki sırası: { sira, toplam, ust_yuzde } ya da skoru yoksa null. Yalnız servis rolü.
create function ortak.kullanici_sirasi(p_oyun text, p_tur text, p_donem text, p_kullanici uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  with s as (select * from ortak.sira_listesi(p_oyun, p_tur, p_donem)),
  t as (select count(*)::int as c from s),
  e as (select coalesce((ayarlar -> 'siralama' ->> 'dagilim_esigi')::int, 50) as esik from ortak.oyunlar where id = p_oyun)
  select jsonb_build_object('sira', s.sira, 'toplam', t.c,
                            'ust_yuzde', case when t.c >= e.esik then ceil(100.0 * s.sira / t.c) end)
  from s, t, e where s.kullanici_id = p_kullanici
$$;

revoke execute on function ortak.sira_listesi(text, text, text) from public, anon, authenticated;
revoke execute on function ortak.kullanici_sirasi(text, text, text, uuid) from public, anon, authenticated;
grant execute on function ortak.kullanici_sirasi(text, text, text, uuid) to service_role;
