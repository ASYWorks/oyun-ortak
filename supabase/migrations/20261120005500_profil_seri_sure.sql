-- Profil günlük kutuları (Halka isteği, kurucu 18 Kasım: "Hedef sayıları yapalım", "A sunucuyu da yapalım").
-- simdiki_seri: bugün ya da dün (İstanbul) biten ardışık çözülen gün; yoksa 0.
-- hedef_sure / hedef_hamle: süresi / hamlesi o günün hedefini aşmayan günlük skor sayısı. Kaynak skorlar.ayrinti
-- (sure, hamle, hedef_sure, hedef_hamle; dogrula-<oyun> yazar). Yalnız puan_surumu >= 4 (Halka v4) sayılır.
-- Saklama: 90 günden eski ayrıntı silinirken bu alanlar ve puan_surumu kalır, sayılar zamanla düşmez.
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
  where oyun_id = p_oyun and kullanici_id = o.kullanici_id and (odul like 'rozet-%' or odul like 'sira:%');

  return jsonb_build_object(
    'ad', o.ad, 'gizli', false, 'ben', coalesce(o.kullanici_id = auth.uid(), false),
    'kademe', o.kademe, 'kademe_adi', a -> 'kademeler' ->> o.kademe,
    'lig', lig, 'katilim', to_char(o.olusturma at time zone 'Europe/Istanbul', 'YYYY-MM'),
    'desen', o.desen, 'gunluk', gunluk, 'etkinlik', etk, 'oduller', odl);
end $$;


-- 90 günlük saklama: ayrıntının yalnız profil ve sürüm alanları kalır (önceden tamamı null'lanıyordu).
select cron.schedule('ortak-saklama', '40 2 * * *', $$
  update ortak.skorlar
    set ayrinti = nullif(jsonb_strip_nulls(jsonb_build_object(
      'puan_surumu', ayrinti -> 'puan_surumu', 'sure', ayrinti -> 'sure', 'hamle', ayrinti -> 'hamle',
      'hedef_sure', ayrinti -> 'hedef_sure', 'hedef_hamle', ayrinti -> 'hedef_hamle')), '{}'::jsonb)
    where ayrinti is not null and olusturma < now() - interval '90 days'
      and ayrinti - array['puan_surumu', 'sure', 'hamle', 'hedef_sure', 'hedef_hamle'] <> '{}'::jsonb;
  delete from ortak.denemeler where guncelleme < now() - interval '90 days';
  delete from ortak.devirler where bitis < now();
$$);
