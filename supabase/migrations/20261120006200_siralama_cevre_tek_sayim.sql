-- 6100 sonrası ölçüm (test projesi, 10.000 skor): oyuncu sırası 31 → 7 ms, ama tablo 76 ms (eski çekirdek 23 ms): çevre
-- penceresinin 21 satırı için sıra ayrı ayrı sayılıyordu. Artık pencerenin ilk satırından iyi olanlar bir kez sayılır;
-- ilk satırla eşit olanlar b0 + 1, diğerleri off + pencere içi rank. Satırlarda yalnız gereken sütunlar taşınır.
-- Doğruluk: tests/sunucu/siralama_olcek.test.ts (eski sira_listesi ile birebir).

create or replace function ortak.siralama(p_oyun text, p_tur text, p_donem text, p_ilk integer default 10, p_cevre integer default 3)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a jsonb;
  esik int;
  ikincilli boolean;
  ben uuid := auth.uid();
  h json := nullif(current_setting('request.headers', true), '')::json;
  t int;
  b_sira int; b_sn int;
  off int;
  ilk_deger numeric; ilk_ikincil numeric; ilk_id bigint;
  b0 int;
  r jsonb;
begin
  -- Dakikada 120 (girişliye kimlikle, girişsize Cloudflare IP'siyle; servis rolü sınırsız).
  if auth.role() is distinct from 'service_role' and not ortak.hiz_siniri('siralama:' || coalesce(ben::text, h ->> 'cf-connecting-ip', 'anon'), 120, 60) then
    raise exception 'cok_istek' using errcode = '54000';
  end if;
  select coalesce(ayarlar -> 'siralama', '{}') into a from ortak.oyunlar where id = p_oyun;
  if not found then raise exception 'oyun_yok'; end if;
  esik := coalesce((a ->> 'dagilim_esigi')::int, 50);
  ikincilli := coalesce(a ->> 'esitlik', 'ortak') = 'ikincil';
  p_ilk := least(greatest(p_ilk, 1), 100);
  p_cevre := least(greatest(p_cevre, 0), 10);

  select count(*)::int into t from ortak.skorlar where oyun_id = p_oyun and tur = p_tur and donem = p_donem;
  if ben is not null then
    select s.sira, s.sn into b_sira, b_sn from ortak.oyuncu_sirasi(p_oyun, p_tur, p_donem, ben) s;
  end if;

  -- Çevre penceresi (ilk N'in dışındaysa): satır sırası b_sn ± p_cevre. Pencerenin ilk satırından iyi olanlar bir kez
  -- sayılır (b0); ilk satırla eşit olanların sırası b0 + 1, diğerlerinin off + pencere içi rank (eşitlikler bitişik).
  off := greatest(coalesce(b_sn, 0) - p_cevre - 1, 0);
  if b_sn is not null and b_sn + p_cevre > p_ilk then
    select s.sira_degeri, s.ikincil, s.id into ilk_deger, ilk_ikincil, ilk_id from ortak.skorlar s
      where s.oyun_id = p_oyun and s.tur = p_tur and s.donem = p_donem
      order by s.sira_degeri desc, case when ikincilli then s.ikincil end asc nulls last, s.id offset off limit 1;
    select r.sira - 1 into b0 from ortak.skor_sirasi(p_oyun, p_tur, p_donem, ilk_deger, ilk_ikincil, ilk_id, ikincilli) r;
  end if;

  with ilk as (
    -- İlk N: indeks sırasıyla; dizinin başı olduğu için rank pencere içinde de genel sıradır.
    select x.kullanici_id, x.puan, x.ikincil,
           rank() over (order by x.sira_degeri desc, case when ikincilli then x.ikincil end asc nulls last)::int as sira,
           row_number() over (order by x.sira_degeri desc, case when ikincilli then x.ikincil end asc nulls last, x.id)::int as sn
    from (select s.kullanici_id, s.puan, s.ikincil, s.sira_degeri, s.id from ortak.skorlar s
          where s.oyun_id = p_oyun and s.tur = p_tur and s.donem = p_donem
          order by s.sira_degeri desc, case when ikincilli then s.ikincil end asc nulls last, s.id limit p_ilk) x
  ),
  cevre as (
    select x.kullanici_id, x.puan, x.ikincil,
           case when x.sira_degeri = ilk_deger and (not ikincilli or x.ikincil is not distinct from ilk_ikincil) then b0 + 1
                else off + (rank() over (order by x.sira_degeri desc, case when ikincilli then x.ikincil end asc nulls last))::int end as sira,
           off + (row_number() over (order by x.sira_degeri desc, case when ikincilli then x.ikincil end asc nulls last, x.id))::int as sn
    from (select s.kullanici_id, s.puan, s.ikincil, s.sira_degeri, s.id from ortak.skorlar s
          where b0 is not null and s.oyun_id = p_oyun and s.tur = p_tur and s.donem = p_donem
          order by s.sira_degeri desc, case when ikincilli then s.ikincil end asc nulls last, s.id
          offset off limit 2 * p_cevre + 1) x
  ),
  satir as (select * from ilk union select * from cevre)
  select jsonb_build_object(
    'toplam', t,
    'kapandi', exists (select 1 from ortak.oduller od where od.oyun_id = p_oyun
                         and od.kaynak = p_tur || ':' || p_donem and od.odul like 'sira:%'),
    'ben', case when b_sira is not null then jsonb_build_object('sira', b_sira,
              'ust_yuzde', case when t >= esik then ceil(100.0 * b_sira / t) end) end,
    'satirlar', coalesce((
      select jsonb_agg(jsonb_build_object('sira', s.sira, 'ad', o.ad, 'puan', s.puan, 'ikincil', s.ikincil, 'profil', o.profil_id,
                                          'ben', coalesce(s.kullanici_id = ben, false)) order by s.sn)
      from satir s left join ortak.oyuncular o on o.oyun_id = p_oyun and o.kullanici_id = s.kullanici_id
      where s.sn <= p_ilk or (b_sn is not null and abs(s.sn - b_sn) <= p_cevre)), '[]'::jsonb))
  into r;
  return r;
end $$;
