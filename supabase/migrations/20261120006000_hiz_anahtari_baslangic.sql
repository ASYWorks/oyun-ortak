-- Güvenlik incelemesi (19 Kasım, 5900 sonrası otomatik inceleme):
-- 1) Hız sınırı anahtarı cf-connecting-ip yoksa istemcinin yazdığı x-forwarded-for'a düşüyordu. Barındırılan ortamda
--    denendi: sahte x-forwarded-for yok sayılıyor (anahtar cf-connecting-ip'den), sahte cf-connecting-ip Cloudflare'de 403.
--    Yani bugün sömürülemez; yine de yedek yol kaldırıldı: başlık yoksa ortak 'anon' kovası. (siralama, sticky.siralama, profil)
-- 2) sticky.siralama'da p_baslangic istemciden de geliyordu: dönem başlangıcı geriye çekilip tarama büyütülebilirdi.
--    Artık yalnız servis rolü (Sticky sunucusu) verebilir.

create or replace function sticky.siralama(p_donem text, p_ilk int default 100, p_baslangic timestamptz default null,
                                p_kullanici uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  -- p_baslangic yalnız servis rolünden (istemci dönemi geriye çekip taramayı büyütemesin).
  bas timestamptz := coalesce(case when auth.role() = 'service_role' then p_baslangic end, sticky.donem_baslangici(p_donem));
  en_az int := case p_donem when 'gun' then 3 when 'hafta' then 5 when 'ay' then 10 else 10 end;
  -- ST-7: servis rolü (Sticky sunucusu) oyuncunun kimliğini verir; başka çağıranda p_kullanici yok sayılır.
  ben uuid := coalesce(case when auth.role() = 'service_role' then p_kullanici end, auth.uid());
  r jsonb;
  h json := nullif(current_setting('request.headers', true), '')::json;
begin
  -- Dakikada 120 (girişliye kimlikle, girişsize IP ile; Sticky sunucusu servis rolüyle sınırsız). Her çağrı dönemin bütün
  -- puan kaydını toplar ve sıralar.
  if auth.role() is distinct from 'service_role' and not ortak.hiz_siniri('sticky-siralama:' || coalesce(auth.uid()::text,
       h ->> 'cf-connecting-ip', 'anon'), 120, 60) then
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

create or replace function ortak.siralama(p_oyun text, p_tur text, p_donem text, p_ilk integer default 10, p_cevre integer default 3)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a jsonb;
  esik int;
  ben uuid := auth.uid();
  r jsonb;
  h json := nullif(current_setting('request.headers', true), '')::json;
begin
  -- Dakikada 120 (girişliye kimlikle, girişsize IP ile; servis rolü sınırsız). Her çağrı günün bütün skorlarını sıralar.
  if auth.role() is distinct from 'service_role' and not ortak.hiz_siniri('siralama:' || coalesce(ben::text, h ->> 'cf-connecting-ip', 'anon'), 120, 60) then
    raise exception 'cok_istek' using errcode = '54000';
  end if;
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
      select jsonb_agg(jsonb_build_object('sira', s.sira, 'ad', o.ad, 'puan', s.puan, 'ikincil', s.ikincil, 'profil', o.profil_id,
                                          'ben', coalesce(s.kullanici_id = ben, false)) order by s.sn)
      from s left join ortak.oyuncular o on o.oyun_id = p_oyun and o.kullanici_id = s.kullanici_id
      where s.sn <= p_ilk or exists (select 1 from b where abs(s.sn - b.sn) <= p_cevre)), '[]'::jsonb))
  into r from t;
  return r;
end $$;

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
    'en_iyi_sira', (select min(s.sira) from e, lateral ortak.sira_listesi(p_oyun, 'etkinlik', e.donem) s
                    where s.kullanici_id = o.kullanici_id),
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
