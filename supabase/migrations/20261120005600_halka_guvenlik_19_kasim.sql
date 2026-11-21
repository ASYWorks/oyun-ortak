-- Halka güvenlik incelemesi 19 Kasım (kurucu 19 Kasım kararları; rapor halka-kelime/docs/inceleme/guvenlik_19_kasim.md).
--
-- B1 süre: nabız kesilerek süre ~15 sn'ye indirilebiliyordu (her aralık en çok 15 sn sayılıyordu).
--   Artık 90 sn'ye kadar durdurulmamış aralık tam sayılır. Durdurulmuş aralık ve 90 sn'den uzun boşluk (örtük duraklatma:
--   arka plandaki telefonda durdur nabzı gitmeyebilir) durak_ms'e yazılır. Teslimde son aralık tam sayılır (sunucu/sure.ts). Duraklatma etkin süreyi ve 2 dakikayı
--   aşarsa oyun skora 'nabiz_boslugu' bayrağı koyar (dogrula-<oyun>; oyun-ortak sunucu/sure.ts nabizBoslugu).
--   Bayraklı skor tabloda kalır, sıra ödülüne (Şampiyon) ve lig puanına girmez.
-- B2 misafir: anlam ve kilit ipucu ile bugünün/turnuvanın kontrolü yalnız kalıcı hesaba. Durumsuz kilit dalı kaldırıldı.
-- B3 rozet: istemcinin yazdığı rozet-… ödülleri profilde yalnız sahibine görünür; başkası yalnız sunucunun verdiği sira:… ödüllerini görür.
--   Seri, çözülen gün, turnuva rozetleri profildeki sunucu istatistiklerinden (gunluk, etkinlik) türetilebilir.

alter table ortak.denemeler add column durak_ms bigint not null default 0;

create or replace function ortak.nabiz(p_oyun text, p_anahtar text, p_durdur boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); d ortak.denemeler;
begin
  if not exists (select 1 from ortak.oyunlar where id = p_oyun) then raise exception 'oyun_yok'; end if;
  if p_anahtar is null or char_length(p_anahtar) not between 1 and 128 then raise exception 'gecersiz'; end if;
  if not ortak.hiz_siniri('nabiz:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  insert into ortak.denemeler as e (oyun_id, kullanici_id, anahtar, son_nabiz, durdu)
    values (p_oyun, u, p_anahtar, now(), false)
    on conflict (oyun_id, kullanici_id, anahtar) do update set
      aktif_ms = case when e.bitti or e.son_nabiz is null or e.durdu or now() - e.son_nabiz > interval '90 seconds' then e.aktif_ms
                      else e.aktif_ms + greatest(0, (extract(epoch from now() - e.son_nabiz) * 1000)::bigint) end,
      durak_ms = case when not e.bitti and e.son_nabiz is not null and (e.durdu or now() - e.son_nabiz > interval '90 seconds')
                      then e.durak_ms + greatest(0, (extract(epoch from now() - e.son_nabiz) * 1000)::bigint)
                      else e.durak_ms end,
      son_nabiz = case when e.bitti then e.son_nabiz else now() end,
      durdu = case when e.bitti then e.durdu else coalesce(p_durdur, false) end
    returning * into d;
  return jsonb_build_object('aktif_ms', d.aktif_ms, 'durak_ms', d.durak_ms, 'bitti', d.bitti, 'durdu', d.durdu);
end $$;

-- Sıra ödülü: nabiz_boslugu bayraklı skor sayılmaz (ne sıraya ne katılımcı sayısına).
create or replace function ortak.siralama_odulu_ver(p_oyun text, p_tur text, p_donem text, p_odul text, p_oran numeric)
returns integer
language plpgsql security definer set search_path = '' as $$
declare a jsonb; yon int; ikincilli boolean; toplam int; n int;
begin
  if p_odul not like 'sira:%' then raise exception 'sira_oneki_gerekli'; end if;
  select coalesce(ayarlar -> 'siralama', '{}') into a from ortak.oyunlar where id = p_oyun;
  yon := case when a ->> 'yon' = 'artan' then -1 else 1 end;
  ikincilli := coalesce(a ->> 'esitlik', 'ortak') = 'ikincil';
  select count(*) into toplam from ortak.skorlar
    where oyun_id = p_oyun and tur = p_tur and donem = p_donem and not ('nabiz_boslugu' = any (bayraklar));
  with s as (
    select kullanici_id,
      rank() over (order by puan * yon desc, case when ikincilli then ikincil end asc nulls last) as sira
    from ortak.skorlar where oyun_id = p_oyun and tur = p_tur and donem = p_donem and not ('nabiz_boslugu' = any (bayraklar))
  )
  insert into ortak.oduller (oyun_id, kullanici_id, odul, kaynak)
    select p_oyun, kullanici_id, p_odul, p_tur || ':' || p_donem from s
    where sira <= greatest(ceil(toplam * p_oran), 1)
    on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- Lig: nabiz_boslugu bayraklı gün lig puanına girmez.
create or replace function ortak.lig_puani_guncelle(p_oyun text, p_kullanici uuid, p_hafta date) returns void
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  select coalesce((ayarlar -> 'lig' ->> 'en_iyi_gun')::int, 5) into n from ortak.oyunlar where id = p_oyun;
  update ortak.lig_uyeleri u set (puan, ikincil) = (
    select coalesce(sum(x.lig_puani), 0), coalesce(sum(x.ikincil), 0) from (
      select s.lig_puani, coalesce(s.ikincil, 0) as ikincil from ortak.skorlar s
      where s.oyun_id = p_oyun and s.kullanici_id = p_kullanici and s.tur = 'gunluk'
        and s.donem between p_hafta::text and (p_hafta + 6)::text and s.lig_puani is not null
        and not ('nabiz_boslugu' = any (s.bayraklar))
      order by s.lig_puani desc, s.ikincil asc nulls last limit n) x)
  where u.oyun_id = p_oyun and u.hafta = p_hafta and u.kullanici_id = p_kullanici
    and not exists (select 1 from ortak.lig_gruplari g where g.id = u.grup_id and g.kapandi);
end $$;

-- B2: bugünün ve turnuvanın kontrolü (ilk temas) yalnız kalıcı hesaba. Girişsiz çağrı zaten gunluk_sinir'de durur.
create or replace function halka.ilk_temas(p_anahtar text) returns void
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid();
begin
  if u is null or ortak.anonim() then raise exception 'hesap_gerekli' using errcode = '28000'; end if;
  if not exists (select 1 from ortak.denemeler where oyun_id = 'halka' and kullanici_id = u and anahtar = p_anahtar) then
    perform ortak.deneme_al('halka', u, p_anahtar);
  end if;
end $$;

create or replace function halka.ipucu_ver(p_anahtar text, p_halkalar jsonb, p_cevaplar text[], p_cozum jsonb, p_anlamlar jsonb,
                                p_kilit_sirasi integer[], p_kurallar jsonb, p_tur text, p_sira integer,
                                p_rot integer[], p_flip boolean[], p_kilitli integer[], p_tema text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid();
  d ortak.denemeler;
  sira int[];
  r int;
  sonuc jsonb;
  kelime text;
begin
  -- Cevabı açan ipuçları yalnız kalıcı hesaba (B2: misafir oturumlarıyla çözüm toplanmasın; günlük ve turnuva hesap ister, A17).
  if p_tur in ('anlam', 'kilit') and (u is null or ortak.anonim()) then
    raise exception 'hesap_gerekli' using errcode = '28000';
  end if;
  -- Duraklatılmış denemede ipucu yok: durdur nabzı geldiyse ya da nabızlı denemede son nabız 15 sn'den eskiyse.
  -- Nabızsız (eski istemci) denemede davranış aynı.
  if u is not null and exists (select 1 from ortak.denemeler e
      where e.oyun_id = 'halka' and e.kullanici_id = u and e.anahtar = p_anahtar and not e.bitti
        and (e.durdu or (e.son_nabiz is not null and e.son_nabiz < now() - interval '15 seconds'))) then
    raise exception 'duraklatildi' using errcode = 'P0001';
  end if;
  -- Hak (src/puan.ts IPUCU_HAK: anlam 2, kilit 2): bitince ipucu yok. Yanıtı kaybolan istek ya da iki cihaz fazladan
  -- ipucu biriktirip dogrula-halka'da 422 ipucu_hakki'na düşürmesin. Satır kilidi aynı anda gelen iki isteği sıraya koyar.
  if u is not null and p_tur in ('anlam', 'kilit') then
    perform 1 from ortak.denemeler where oyun_id = 'halka' and kullanici_id = u and anahtar = p_anahtar for update;
    if (select count(*) from ortak.denemeler e, jsonb_array_elements_text(coalesce(e.durum -> 'ipuclari', '[]')) x
        where e.oyun_id = 'halka' and e.kullanici_id = u and e.anahtar = p_anahtar and x = p_tur) >= 2 then
      return null;
    end if;
  end if;
  if p_tur = 'anlam' then
    -- Durum geldiyse p_sira oyuncunun yerleşimindeki dilim: çerçevede o dilimde okunan kelime. Yoksa asıl çözümün cevabı.
    if p_cozum is not null and (p_rot is not null or p_flip is not null) then
      if not halka.durum_gecerli(jsonb_array_length(p_halkalar), p_rot, p_flip) then
        raise exception 'gecersiz_durum' using errcode = '22023';
      end if;
      kelime := halka.dilim_oku(p_halkalar,
        halka.cerceve(p_halkalar, p_cozum, p_kurallar, halka.kilitliler(p_anahtar, p_kurallar, p_kilitli), p_rot, p_flip), p_sira);
    else
      kelime := p_cevaplar[p_sira + 1];
    end if;
    sonuc := case when p_anlamlar ->> kelime is not null then jsonb_build_object('anlam', p_anlamlar ->> kelime) end;
  elsif p_tur = 'kilit' then
    if p_cozum is null then return null; end if;
    if p_rot is not null or p_flip is not null then
      if not halka.durum_gecerli(jsonb_array_length(p_halkalar), p_rot, p_flip) then
        raise exception 'gecersiz_durum' using errcode = '22023';
      end if;
      sonuc := halka.kilit_sec(p_halkalar, p_cozum, p_kurallar, halka.kilitliler(p_anahtar, p_kurallar, p_kilitli),
        p_kilit_sirasi, p_rot, p_flip);
    else
      -- Durumsuz kilit (asıl çözümden sira. halka) kaldırıldı: istemci her zaman durum gönderir (B2).
      raise exception 'durum_gerekli' using errcode = '22023';
    end if;
  elsif p_tur = 'tema' then
    sonuc := jsonb_strip_nulls(jsonb_build_object('tema', p_tema));
  else
    raise exception 'gecersiz_tur' using errcode = '22023';
  end if;
  if sonuc is not null and u is not null then
    d := ortak.deneme_al('halka', u, p_anahtar);
    -- Tema ipucu bir kez sayılır: başlığı kaybeden istemci yeniden isteyebilir.
    if not (p_tur = 'tema' and coalesce(d.durum -> 'ipuclari', '[]'::jsonb) ? 'tema') then
      update ortak.denemeler
         set durum = durum || jsonb_build_object('ipuclari', coalesce(durum -> 'ipuclari', '[]'::jsonb) || to_jsonb(p_tur))
                   || case when p_tur = 'kilit' and not coalesce(durum -> 'kilitli', '[]'::jsonb) @> jsonb_build_array(sonuc -> 'halka')
                           then jsonb_build_object('kilitli', coalesce(durum -> 'kilitli', '[]'::jsonb) || (sonuc -> 'halka'))
                           else '{}'::jsonb end,
             guncelleme = now()
       where oyun_id = 'halka' and kullanici_id = u and anahtar = p_anahtar and not bitti;
    end if;
  end if;
  return sonuc;
end $$;

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
  where oyun_id = p_oyun and kullanici_id = o.kullanici_id and (odul like 'sira:%' or (odul like 'rozet-%' and o.kullanici_id = auth.uid()));

  return jsonb_build_object(
    'ad', o.ad, 'gizli', false, 'ben', coalesce(o.kullanici_id = auth.uid(), false),
    'kademe', o.kademe, 'kademe_adi', a -> 'kademeler' ->> o.kademe,
    'lig', lig, 'katilim', to_char(o.olusturma at time zone 'Europe/Istanbul', 'YYYY-MM'),
    'desen', o.desen, 'gunluk', gunluk, 'etkinlik', etk, 'oduller', odl);
end $$;

-- ---------------------------------------------------------------- oyun-ortak sunucu incelemesi (19 Kasım, kurucu)
-- S1: kayit_yaz'da hız sınırı yoktu; 256 KB'lık yazım sınırsız tekrarlanıp veritabanını şişirebilirdi. Dakikada 30.
create or replace function ortak.kayit_yaz(p_oyun text, p_veri jsonb, p_surum integer) returns integer
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); yeni integer;
begin
  if ortak.anonim() then raise exception 'kalici_hesap_gerekli'; end if;
  if octet_length(p_veri::text) > 262144 then raise exception 'kayit_buyuk' using errcode = '22001'; end if;
  if not ortak.hiz_siniri('kayit:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  if p_surum = 0 then
    insert into ortak.kayitlar (oyun_id, kullanici_id, veri) values (p_oyun, u, p_veri)
      on conflict do nothing returning surum into yeni;
  else
    update ortak.kayitlar set veri = p_veri, surum = surum + 1, guncelleme = now()
      where oyun_id = p_oyun and kullanici_id = u and surum = p_surum
      returning surum into yeni;
  end if;
  return yeni;
end $$;

-- S2 (Beat Greedy ligleri): kurucu doğrudan UPDATE ile owner_id'yi üye olmayana, invite_code'u istediği değere
-- çevirebiliyordu (transfer_league ve rotate_league_code denetimlerini atlayarak). İstemci UPDATE kullanmıyor; kapatıldı.
-- Oluştururken yalnız ad, açıklama ve kurucu yazılır (davet kodu sunucuda üretilir).
revoke update on sezgi.leagues from authenticated, anon;
revoke insert on sezgi.leagues from authenticated, anon;
grant insert (name, description, owner_id) on sezgi.leagues to authenticated;

-- Lig (kurucu 19 Kasım, Halka puan v5 tabanı 0): o hafta günlük skoru olan oyuncu puanı 0 da olsa oynamış sayılır,
-- sıraya girer ve kademe kuralları işler (önceden puan > 0 şartı vardı). Hiç oynamayan yine sıraya girmez.
create or replace function ortak.lig_kapat() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  g ortak.lig_gruplari;
  a jsonb;
  ust int;
  kapanan int := 0;
begin
  for g in
    select * from ortak.lig_gruplari
    where not kapandi and hafta < ortak.iso_hafta(ortak.bugun())
    order by id for update skip locked
  loop
    select ayarlar -> 'lig' into a from ortak.oyunlar where id = g.oyun_id;
    ust := greatest(coalesce(jsonb_array_length(a -> 'kademeler'), 1) - 1, 0);

    with r as (
      select l.kullanici_id,
        rank() over (order by l.puan desc,
          case when coalesce(a ->> 'esitlik', 'ortak') = 'ikincil' then l.ikincil end asc nulls last) as sira
      from ortak.lig_uyeleri l where l.grup_id = g.id
        and exists (select 1 from ortak.skorlar s where s.oyun_id = g.oyun_id and s.kullanici_id = l.kullanici_id
                      and s.tur = 'gunluk' and s.donem between g.hafta::text and (g.hafta + 6)::text)
    ), sayi as (select count(*)::int as c from r)
    update ortak.lig_uyeleri u set
      sira = r.sira,
      sonuc = case
        when r.sira <= floor(sayi.c * coalesce((a ->> 'cikis_orani')::numeric, 0.2)) and g.kademe < ust then 'cikti'
        when r.sira > sayi.c - floor(sayi.c * coalesce((a ->> 'inis_orani')::numeric, 0.2)) and g.kademe > 0 then 'indi'
        else 'kaldi' end
    from r, sayi
    where u.grup_id = g.id and u.kullanici_id = r.kullanici_id;

    update ortak.lig_uyeleri set sonuc = 'kaldi' where grup_id = g.id and sonuc is null;

    update ortak.oyuncular o set kademe = o.kademe + case u.sonuc when 'cikti' then 1 else -1 end
    from ortak.lig_uyeleri u
    where u.grup_id = g.id and u.sonuc in ('cikti', 'indi')
      and o.oyun_id = g.oyun_id and o.kullanici_id = u.kullanici_id;

    if coalesce((a ->> 'kademe_odulu')::boolean, false) then
      insert into ortak.oduller (oyun_id, kullanici_id, odul, kaynak)
        select g.oyun_id, u.kullanici_id, 'sira:lig-' || (g.kademe + 1) || '-' || g.hafta, 'lig:' || g.hafta
        from ortak.lig_uyeleri u where u.grup_id = g.id and u.sonuc = 'cikti'
        on conflict do nothing;
    end if;

    update ortak.lig_gruplari set kapandi = true where id = g.id;
    kapanan := kapanan + 1;
  end loop;
  return kapanan;
end $$;

-- Beat Greedy aynı süre açığı (kurucu 19 Kasım "Halka gibi"): sezgi.nabiz 90 sn'ye kadar aralığı tam sayar; durdurulmuş
-- aralık ve daha uzun boşluk durak_ms'e. Teslimde son aralık tam; duraklatma etkin süreyi ve 2 dk'yı aşarsa 'nabiz_boslugu'.
-- Bayraklı deneme tabloda kalır; günlük toplamı lige yazan submit_attempt bayrağı dışarıda bırakmalı (Beat Greedy deposu).
alter table sezgi.attempts add column durak_ms integer not null default 0;

create or replace function sezgi.nabiz(p_attempt bigint, p_durdur boolean default false) returns jsonb
language plpgsql security definer set search_path = sezgi as $$
declare u uuid := auth.uid(); r record;
begin
  if u is null then raise exception 'giris_gerekli'; end if;
  if not ortak.hiz_siniri('sezgi-nabiz:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  update attempts a set
    aktif_ms = case when a.son_nabiz is null or a.durdu or now() - a.son_nabiz > interval '90 seconds' then a.aktif_ms
                    else a.aktif_ms + greatest(0, (extract(epoch from now() - a.son_nabiz) * 1000)::int) end,
    durak_ms = case when a.son_nabiz is not null and (a.durdu or now() - a.son_nabiz > interval '90 seconds')
                    then a.durak_ms + least(greatest(0, (extract(epoch from now() - a.son_nabiz) * 1000)::bigint), 86400000)::int
                    else a.durak_ms end,
    son_nabiz = now(),
    durdu = coalesce(p_durdur, false)
  from daily_puzzles p
  where a.id = p_attempt and a.user_id = u and p.id = a.puzzle_id and a.status = 'started' and now() < attempt_deadline(p.day)
  returning a.aktif_ms, a.durak_ms, a.durdu into r;
  if not found then return jsonb_build_object('error', 'attempt_closed'); end if;
  return jsonb_build_object('aktif_ms', r.aktif_ms, 'durak_ms', r.durak_ms, 'durdu', r.durdu);
end $$;

create or replace function sezgi.finish_attempt_tx(
  p_attempt bigint, p_user uuid, p_value double precision, p_score int, p_solution jsonb,
  p_client_ms int, p_min_ms int, p_beaten boolean, p_retried boolean, p_reached boolean
) returns jsonb language plpgsql set search_path = sezgi set extra_float_digits = 1 as $$
declare
  a attempts;
  p daily_puzzles;
  already boolean;
  ms int;
  fl text[] := '{}';
begin
  select * into a from attempts where id = p_attempt and user_id = p_user for update;
  if not found then return jsonb_build_object('error', 'attempt_not_found'); end if;
  select * into p from daily_puzzles where id = a.puzzle_id;
  already := a.status <> 'started';
  if not already then
    if now() >= attempt_deadline(p.day) then
      update attempts set status = 'timeout', score = 0,
        duration_ms = round(extract(epoch from attempt_deadline(p.day) - a.started_at) * 1000)::int
      where id = a.id returning * into a;
    else
      -- Nabız geldiyse ekranda geçen süre (duraklatma sayılmaz), gelmediyse duvar saati.
      -- Teslimde durdu yok sayılır; son aralık tam sayılır (19 Kasım B1). Duraklatma etkin süreyi ve 2 dk'yı aşarsa bayrak.
      ms := case when a.son_nabiz is null then round(extract(epoch from now() - a.started_at) * 1000)::int
                 else a.aktif_ms + greatest(0, round(extract(epoch from now() - a.son_nabiz) * 1000)::int) end;
      if ms < p_min_ms then fl := array_append(fl, 'too_fast'); end if;
      if p_client_ms is not null and abs(ms - p_client_ms) > 10000 then fl := array_append(fl, 'clock_mismatch'); end if;
      if p_retried then fl := array_append(fl, 'connection_lost'); end if;
      if a.son_nabiz is not null and a.durak_ms > greatest(ms, 120000) then fl := array_append(fl, 'nabiz_boslugu'); end if;
      if p.day < istanbul_today() then fl := array_append(fl, 'after_day_end'); end if;
      update attempts set status = 'submitted', submitted_at = now(), duration_ms = ms, client_ms = p_client_ms,
        value = p_value, score = p_score, solution = p_solution, flags = fl,
        reached = case when p.kind = 'race' then coalesce(p_reached, false) end
      where id = a.id returning * into a;
      if p_beaten then
        update daily_puzzles set target_beaten = true where id = p.id returning * into p;
      end if;
    end if;
  end if;
  return jsonb_build_object(
    'attempt_id', a.id, 'kind', p.kind, 'status', a.status, 'value', a.value, 'score', a.score,
    'duration_ms', a.duration_ms, 'submitted_at', a.submitted_at, 'flags', a.flags,
    'hints', a.hints, 'reached', a.reached,
    'target_value', p.target_value, 'greedy_value', p.greedy_value, 'target_beaten', p.target_beaten,
    'already_final', already);
end $$;
