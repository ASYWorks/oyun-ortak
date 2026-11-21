-- Sıralama ölçeklenmesi (19 Kasım, kurucu "Başla"; 10 bin eşzamanlı hedefi). siralama ve kullanici_sirasi her çağrıda
-- günün bütün skorlarını sira_listesi ile baştan sıralıyordu (2000 skorda 8 ms, oyuncu sayısıyla doğrusal; her gönderimde
-- bir kez, tablo açılınca bir kez daha). Artık:
--   - skorlar.sira_degeri = puan × yön (büyük olan önde), tetikleyiciyle yazılır; oyunun yönü değişirse yeniden hesaplanır.
--   - Tek indeks (oyun, tür, dönem, sira_degeri desc, ikincil, id): ilk N indeksten okunur, oyuncunun sırası ondan iyi
--     olanların sayısıdır (yalnız önündeki satırlar taranır).
-- Sonuçlar sira_listesi ile birebir aynı (rank: eşit puan aynı sıra; esitlik 'ikincil' ise küçük ikincil önde, boş en sonda;
-- satır sırası eşitlikte id). sira_listesi kalır (ödül ve kapanış işleri dakikada bir değil, dönem sonunda bir kez çalışır).
-- Doğruluk testi: tests/sunucu/siralama_olcek.test.ts (rastgele veride eski ve yeni karşılaştırması, dört ayar).

alter table ortak.skorlar add column sira_degeri numeric;

create function ortak.oyun_yonu(p_oyun text) returns integer
language sql stable set search_path = '' as $$
  select case when ayarlar -> 'siralama' ->> 'yon' = 'artan' then -1 else 1 end from ortak.oyunlar where id = p_oyun
$$;

create function ortak.sira_degeri_yaz() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.sira_degeri := new.puan * ortak.oyun_yonu(new.oyun_id);
  return new;
end $$;
create trigger skorlar_sira_degeri before insert or update of puan, oyun_id on ortak.skorlar
  for each row execute function ortak.sira_degeri_yaz();

create function ortak.oyun_yonu_degisti() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (old.ayarlar -> 'siralama' ->> 'yon') is distinct from (new.ayarlar -> 'siralama' ->> 'yon') then
    update ortak.skorlar set sira_degeri = puan * ortak.oyun_yonu(new.id) where oyun_id = new.id;
  end if;
  return new;
end $$;
create trigger oyunlar_yon after update of ayarlar on ortak.oyunlar
  for each row execute function ortak.oyun_yonu_degisti();

update ortak.skorlar s set sira_degeri = s.puan * ortak.oyun_yonu(s.oyun_id);
alter table ortak.skorlar alter column sira_degeri set not null;
create index skorlar_sira on ortak.skorlar (oyun_id, tur, donem, sira_degeri desc, ikincil asc nulls last, id);

revoke execute on function ortak.oyun_yonu(text), ortak.sira_degeri_yaz(), ortak.oyun_yonu_degisti() from public, anon, authenticated;

-- Bir skorun sırası (rank) ve satır sırası (sn): yalnız ondan iyi ya da eşit puanlı satırlar sayılır.
create function ortak.skor_sirasi(p_oyun text, p_tur text, p_donem text, p_deger numeric, p_ikincil numeric, p_id bigint,
                                  p_ikincilli boolean)
returns table (sira integer, sn integer)
language sql stable set search_path = '' as $$
  select 1 + (count(*) filter (where s.sira_degeri > p_deger
                or (p_ikincilli and s.sira_degeri = p_deger and s.ikincil is not null and (p_ikincil is null or s.ikincil < p_ikincil))))::int,
         1 + (count(*) filter (where s.sira_degeri > p_deger
                or (s.sira_degeri = p_deger and (not p_ikincilli or s.ikincil is not distinct from p_ikincil) and s.id < p_id)
                or (p_ikincilli and s.sira_degeri = p_deger and s.ikincil is not null and (p_ikincil is null or s.ikincil < p_ikincil))))::int
  from ortak.skorlar s
  where s.oyun_id = p_oyun and s.tur = p_tur and s.donem = p_donem and s.sira_degeri >= p_deger
$$;
revoke execute on function ortak.skor_sirasi(text, text, text, numeric, numeric, bigint, boolean) from public, anon, authenticated;

-- Oyuncunun sırası (yoksa boş satır).
create function ortak.oyuncu_sirasi(p_oyun text, p_tur text, p_donem text, p_kullanici uuid)
returns table (sira integer, sn integer)
language sql stable set search_path = '' as $$
  select r.sira, r.sn
  from ortak.skorlar b,
       lateral ortak.skor_sirasi(p_oyun, p_tur, p_donem, b.sira_degeri, b.ikincil, b.id,
                                 coalesce((select ayarlar -> 'siralama' ->> 'esitlik' from ortak.oyunlar where id = p_oyun), 'ortak') = 'ikincil') r
  where b.oyun_id = p_oyun and b.tur = p_tur and b.donem = p_donem and b.kullanici_id = p_kullanici
$$;
revoke execute on function ortak.oyuncu_sirasi(text, text, text, uuid) from public, anon, authenticated;

create or replace function ortak.kullanici_sirasi(p_oyun text, p_tur text, p_donem text, p_kullanici uuid)
returns jsonb
language sql stable security definer set search_path = '' as $$
  with t as (select count(*)::int as c from ortak.skorlar where oyun_id = p_oyun and tur = p_tur and donem = p_donem),
  e as (select coalesce((ayarlar -> 'siralama' ->> 'dagilim_esigi')::int, 50) as esik from ortak.oyunlar where id = p_oyun)
  select jsonb_build_object('sira', s.sira, 'toplam', t.c,
                            'ust_yuzde', case when t.c >= e.esik then ceil(100.0 * s.sira / t.c) end)
  from ortak.oyuncu_sirasi(p_oyun, p_tur, p_donem, p_kullanici) s, t, e
$$;
revoke execute on function ortak.kullanici_sirasi(text, text, text, uuid) from public, anon, authenticated;
grant execute on function ortak.kullanici_sirasi(text, text, text, uuid) to service_role;

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

  with ilk as (
    -- İlk N: indeks sırasıyla; dizinin başı olduğu için rank pencere içinde de genel sıradır.
    select x.*, rank() over (order by x.sira_degeri desc, case when ikincilli then x.ikincil end asc nulls last)::int as sira,
           row_number() over (order by x.sira_degeri desc, case when ikincilli then x.ikincil end asc nulls last, x.id)::int as sn
    from (select * from ortak.skorlar s where s.oyun_id = p_oyun and s.tur = p_tur and s.donem = p_donem
          order by s.sira_degeri desc, case when ikincilli then s.ikincil end asc nulls last, s.id limit p_ilk) x
  ),
  cevre as (
    -- Oyuncunun çevresi (ilk N'in dışındaysa): satır sırası b_sn ± p_cevre; sıra satır başına sayılır.
    select x.*, r.sira, r.sn
    from (select * from ortak.skorlar s where b_sn is not null and b_sn + p_cevre > p_ilk
            and s.oyun_id = p_oyun and s.tur = p_tur and s.donem = p_donem
          order by s.sira_degeri desc, case when ikincilli then s.ikincil end asc nulls last, s.id
          offset greatest(b_sn - p_cevre - 1, 0) limit 2 * p_cevre + 1) x,
         lateral ortak.skor_sirasi(p_oyun, p_tur, p_donem, x.sira_degeri, x.ikincil, x.id, ikincilli) r
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

-- Profil: en iyi turnuva sırası oyuncu_sirasi ile (etkinlik başına bütün liste sıralanmaz).
create or replace function ortak.profil(p_oyun text, p_profil uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  h json := nullif(current_setting('request.headers', true), '')::json;
  anahtar text := 'profil:' || coalesce(auth.uid()::text, h ->> 'cf-connecting-ip', 'anon');
  o ortak.oyuncular;
  a jsonb;
  v_hafta date := ortak.iso_hafta(ortak.bugun());
  lig jsonb; gunluk jsonb; etk jsonb; odl jsonb;
begin
  if not ortak.hiz_siniri(anahtar, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  select * into o from ortak.oyuncular where oyun_id = p_oyun and profil_id = p_profil;
  if not found then return null; end if;
  if exists (select 1 from auth.users where id = o.kullanici_id and is_anonymous) then return null; end if;
  if o.profil_gizli and o.kullanici_id is distinct from auth.uid() then
    return jsonb_build_object('ad', o.ad, 'gizli', true);
  end if;
  select ayarlar -> 'lig' into a from ortak.oyunlar where id = p_oyun;

  select jsonb_build_object('sira', x.sira, 'kisi', x.kisi) into lig from (
    select l.kullanici_id, rank() over (order by l.puan desc,
             case when coalesce(a ->> 'esitlik', 'ortak') = 'ikincil' then l.ikincil end asc nulls last) as sira,
           count(*) over () as kisi
    from ortak.lig_uyeleri l
    where l.grup_id = (select grup_id from ortak.lig_uyeleri
                       where oyun_id = p_oyun and hafta = v_hafta and kullanici_id = o.kullanici_id)) x
  where x.kullanici_id = o.kullanici_id;

  with g as (select donem::date as gun, lig_puani, ayrinti as y from ortak.skorlar
             where oyun_id = p_oyun and kullanici_id = o.kullanici_id and tur = 'gunluk'),
  ada as (select gun, gun - (row_number() over (order by gun))::int as k from g),
  v4 as (select (y ->> 'sure')::numeric as sure, (y ->> 'hamle')::numeric as hamle,
                (y ->> 'hedef_sure')::numeric as hs, (y ->> 'hedef_hamle')::numeric as hh
         from g where coalesce((y ->> 'puan_surumu')::int, 0) >= 4)
  select jsonb_build_object(
    'cozulen', (select count(*) from g),
    'en_uzun_seri', coalesce((select max(n) from (select count(*) as n from ada group by k) s), 0),
    'simdiki_seri', coalesce((select count(*) from ada where k = (select k from ada order by gun desc limit 1)
                                and exists (select 1 from g where g.gun >= ortak.bugun() - 1)), 0),
    'hedef_sure', (select count(*) from v4 where sure <= hs),
    'hedef_hamle', (select count(*) from v4 where hamle <= hh),
    'ortalama_puan', (select round(avg(lig_puani)) from g where lig_puani is not null),
    'yuz_ustu', (select count(*) from g where lig_puani >= 100))
  into gunluk;

  with e as (select distinct donem from ortak.skorlar
             where oyun_id = p_oyun and kullanici_id = o.kullanici_id and tur = 'etkinlik')
  select jsonb_build_object(
    'katildi', (select count(*) from e),
    'en_iyi_sira', (select min(s.sira) from e, lateral ortak.oyuncu_sirasi(p_oyun, 'etkinlik', e.donem, o.kullanici_id) s),
    'sampiyon', (select count(*) from ortak.oduller where oyun_id = p_oyun and kullanici_id = o.kullanici_id
                 and odul like 'sira:%' and kaynak like 'etkinlik:%'))
  into etk;

  select coalesce(jsonb_agg(jsonb_build_object('odul', odul, 'kazanildi', kazanildi) order by kazanildi), '[]'::jsonb)
  into odl from ortak.oduller
  where oyun_id = p_oyun and kullanici_id = o.kullanici_id and (odul like 'sira:%' or (odul like 'rozet-%' and o.kullanici_id = auth.uid()));

  return jsonb_build_object(
    'ad', o.ad, 'gizli', false, 'ben', coalesce(o.kullanici_id = auth.uid(), false),
    'kademe', o.kademe, 'kademe_adi', a -> 'kademeler' ->> o.kademe,
    'lig', lig, 'katilim', to_char(o.olusturma at time zone 'Europe/Istanbul', 'YYYY-MM'),
    'desen', o.desen, 'gunluk', gunluk, 'etkinlik', etk, 'oduller', odl);
end $$;
