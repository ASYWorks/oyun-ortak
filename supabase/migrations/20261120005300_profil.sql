-- Oyuncu profili (Halka isteği, kurucu 18 Kasım; belirtim halka-kelime/docs/PROFIL.md).
-- Profil varsayılan görünür, oyuncu kapatabilir. Misafir ve girişsiz ziyaretçi başkasının profilini görebilir.
-- Kullanıcı kimliği dışarı çıkmaz: tablo satırları rastgele `profil` kimliği taşır (oyuncular.profil_id).
-- Günlük istatistik oyun puanından (skorlar.lig_puani; Halka'da 0–120 oyun puanı) hesaplanır; etkinlik sırası
-- ortak.sira_listesi'nden, Şampiyon sayısı `sira:` önekli ödüllerden.

alter table ortak.oyuncular
  add column profil_id uuid not null default gen_random_uuid(),
  add column profil_gizli boolean not null default false,
  add column desen text check (desen ~ '^[a-z0-9_.-]{1,40}$');
create unique index oyuncular_profil_id on ortak.oyuncular (profil_id);

-- Tablo satırlarına profil kimliği.
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
      select jsonb_agg(jsonb_build_object('sira', s.sira, 'ad', o.ad, 'puan', s.puan, 'ikincil', s.ikincil, 'profil', o.profil_id,
                                          'ben', coalesce(s.kullanici_id = ben, false)) order by s.sn)
      from s left join ortak.oyuncular o on o.oyun_id = p_oyun and o.kullanici_id = s.kullanici_id
      where s.sn <= p_ilk or exists (select 1 from b where abs(s.sn - b.sn) <= p_cevre)), '[]'::jsonb))
  into r from t;
  return r;
end $$;

create or replace function ortak.lig_durumu(p_oyun text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  u uuid := ortak.kim();
  v_hafta date := ortak.iso_hafta(ortak.bugun());
  a jsonb;
  g bigint;
  o ortak.oyuncular;
  onceki jsonb;
  uyeler jsonb;
begin
  select ayarlar -> 'lig' into a from ortak.oyunlar where id = p_oyun;
  if a is null then raise exception 'lig_yok'; end if;
  select * into o from ortak.oyuncular where oyun_id = p_oyun and kullanici_id = u;
  select jsonb_build_object('hafta', l.hafta, 'sira', l.sira, 'sonuc', l.sonuc, 'puan', l.puan) into onceki
    from ortak.lig_uyeleri l join ortak.lig_gruplari gr on gr.id = l.grup_id
    where l.oyun_id = p_oyun and l.kullanici_id = u and gr.kapandi
    order by l.hafta desc limit 1;
  select grup_id into g from ortak.lig_uyeleri where oyun_id = p_oyun and hafta = v_hafta and kullanici_id = u;

  if g is not null then
    select jsonb_agg(jsonb_build_object('sira', x.sira, 'ad', x.ad, 'puan', x.puan, 'ikincil', x.ikincil, 'profil', x.profil, 'ben', x.ben) order by x.sira, x.ad)
    into uyeler from (
      select rank() over (order by l.puan desc,
               case when coalesce(a ->> 'esitlik', 'ortak') = 'ikincil' then l.ikincil end asc nulls last) as sira,
             oy.ad, oy.profil_id as profil, l.puan,
             case when coalesce(a ->> 'esitlik', 'ortak') = 'ikincil' then l.ikincil end as ikincil,
             l.kullanici_id = u as ben
      from ortak.lig_uyeleri l
      left join ortak.oyuncular oy on oy.oyun_id = p_oyun and oy.kullanici_id = l.kullanici_id
      where l.grup_id = g) x;
  end if;

  return jsonb_build_object(
    'hafta', v_hafta,
    'kademe', coalesce(o.kademe, 0),
    'kademe_adi', a -> 'kademeler' ->> coalesce(o.kademe, 0),
    'katildi', g is not null,
    'uyeler', coalesce(uyeler, '[]'::jsonb),
    'onceki', onceki);
end $$;

-- Profil. Dakikada 30 istek (girişliye kimlikle, girişsize IP ile). Bulunamazsa null; gizliyse yalnız ad.
create function ortak.profil(p_oyun text, p_profil uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  h json := nullif(current_setting('request.headers', true), '')::json;
  anahtar text := 'profil:' || coalesce(auth.uid()::text, h ->> 'cf-connecting-ip', split_part(h ->> 'x-forwarded-for', ',', 1), 'anon');
  o ortak.oyuncular;
  a jsonb;
  v_hafta date := ortak.iso_hafta(ortak.bugun());
  lig jsonb; gunluk jsonb; etk jsonb; odl jsonb;
begin
  if not ortak.hiz_siniri(anahtar, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  select * into o from ortak.oyuncular where oyun_id = p_oyun and profil_id = p_profil;
  if not found then return null; end if;
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

  with g as (select donem::date as gun, lig_puani from ortak.skorlar
             where oyun_id = p_oyun and kullanici_id = o.kullanici_id and tur = 'gunluk'),
  ada as (select gun - (row_number() over (order by gun))::int as k from g)
  select jsonb_build_object(
    'cozulen', (select count(*) from g),
    'en_uzun_seri', coalesce((select max(n) from (select count(*) as n from ada group by k) s), 0),
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
  where oyun_id = p_oyun and kullanici_id = o.kullanici_id and (odul like 'rozet-%' or odul like 'sira:%');

  return jsonb_build_object(
    'ad', o.ad, 'gizli', false, 'ben', coalesce(o.kullanici_id = auth.uid(), false),
    'kademe', o.kademe, 'kademe_adi', a -> 'kademeler' ->> o.kademe,
    'lig', lig, 'katilim', to_char(o.olusturma at time zone 'Europe/Istanbul', 'YYYY-MM'),
    'desen', o.desen, 'gunluk', gunluk, 'etkinlik', etk, 'oduller', odl);
end $$;

-- Kendi profil ayarı. null = değiştirme; desen '' = kaldır. Oyuncu satırı yoksa açılmaz (sıralamaya girince açılır).
create function ortak.profil_ayari(p_oyun text, p_gizli boolean default null, p_desen text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); o ortak.oyuncular;
begin
  if not ortak.hiz_siniri('profil_ayari:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  update ortak.oyuncular set
    profil_gizli = coalesce(p_gizli, profil_gizli),
    desen = case when p_desen is null then desen else nullif(p_desen, '') end
  where oyun_id = p_oyun and kullanici_id = u
  returning * into o;
  if not found then return null; end if;
  return jsonb_build_object('profil', o.profil_id, 'gizli', o.profil_gizli, 'desen', o.desen);
end $$;

revoke execute on function ortak.profil(text, uuid), ortak.profil_ayari(text, boolean, text) from public, anon, authenticated;
grant execute on function ortak.profil(text, uuid) to anon, authenticated;
grant execute on function ortak.profil_ayari(text, boolean, text) to authenticated;
