-- Misafirin profili yok (kurucu 18 Kasım). Misafir sıralamaya ve lige girmediği için profil kimliği zaten görünmez;
-- ayrıca profil ayarı kaydedemez ve misafir hesabın profili kimseye dönmez. Böylece hesap devrinde taşınacak
-- profil ayarı oluşmaz (güvenlik incelemesi: devirde misafirin gizlilik ayarı düşüyordu).
create or replace function ortak.profil(p_oyun text, p_profil uuid) returns jsonb
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

create or replace function ortak.profil_ayari(p_oyun text, p_gizli boolean default null, p_desen text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); o ortak.oyuncular;
begin
  if ortak.anonim() then raise exception 'misafir' using errcode = '42501'; end if;
  if not ortak.hiz_siniri('profil_ayari:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  update ortak.oyuncular set
    profil_gizli = coalesce(p_gizli, profil_gizli),
    desen = case when p_desen is null then desen else nullif(p_desen, '') end
  where oyun_id = p_oyun and kullanici_id = u
  returning * into o;
  if not found then return null; end if;
  return jsonb_build_object('profil', o.profil_id, 'gizli', o.profil_gizli, 'desen', o.desen);
end $$;
