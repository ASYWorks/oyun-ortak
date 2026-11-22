-- Göç 8220: 8210 güvenlik düzeltmesi (otomatik inceleme, 22 Kasım).
-- 1) Arkadaşlık kodla kurulur (kodu paylaşmak rızadır, Koz tasarımı); ama oyuncunun çıkış yolu yoktu. Eklenenler:
--    koz_arkadas_sil (iki yönü siler), koz_kod_yenile (eski kod geçersiz olur), hedef tarafta da 100 sınırı.
-- 2) Günde 3 düello sınırı paralel isteklerle aşılabiliyordu: sayımdan önce kullanıcı başına işlem kilidi.

create or replace function public.koz_arkadas_ekle(p_kod text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim(); a uuid;
begin
  if not ortak.hiz_siniri('koz-ark:' || u, 20, 3600) then raise exception 'cok_istek' using errcode = '54000'; end if;
  select kullanici into a from koz.arkadas_kodu where kod = upper(trim(p_kod));
  if a is null then return jsonb_build_object('hata', 'kod_yok'); end if;
  if a = u then return jsonb_build_object('hata', 'kendin'); end if;
  if (select count(*) from koz.arkadaslik where kullanici = u) >= 100
     or (select count(*) from koz.arkadaslik where kullanici = a) >= 100 then
    return jsonb_build_object('hata', 'sinir');
  end if;
  insert into koz.arkadaslik (kullanici, arkadas) values (u, a), (a, u) on conflict do nothing;
  return jsonb_build_object('tamam', true);
end $$;

-- Arkadaşı adıyla siler (istemci kimlik görmez). İki yön birlikte gider; açılmış düellolar kalır (geçmiş).
create function public.koz_arkadas_sil(p_ad text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim(); a uuid;
begin
  select r.arkadas into a from koz.arkadaslik r
    join ortak.oyuncular o on o.oyun_id = 'koz' and o.kullanici_id = r.arkadas
   where r.kullanici = u and o.ad = p_ad;
  if a is null then return jsonb_build_object('hata', 'arkadas_yok'); end if;
  delete from koz.arkadaslik where (kullanici = u and arkadas = a) or (kullanici = a and arkadas = u);
  return jsonb_build_object('tamam', true);
end $$;

-- Yeni kod üretir; eski kod artık eşleşmez (mevcut arkadaşlıklar kalır).
create function public.koz_kod_yenile() returns text language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim();
begin
  if not ortak.hiz_siniri('koz-kod:' || u, 5, 86400) then raise exception 'cok_istek' using errcode = '54000'; end if;
  delete from koz.arkadas_kodu where kullanici = u;
  return public.koz_kodum();
end $$;

create or replace function public.koz_duello_ac(p_kod text, p_el int) returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim(); r uuid; secim text[]; yeni uuid;
  gun_bas timestamptz := (ortak.bugun())::timestamp at time zone 'Europe/Istanbul';
begin
  if p_el not in (3, 5) then raise exception 'el_sayisi' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('koz-duello:' || u));
  select kullanici into r from koz.arkadas_kodu where kod = upper(trim(p_kod));
  if r is null or not exists (select 1 from koz.arkadaslik where kullanici = u and arkadas = r) then
    raise exception 'arkadas_degil' using errcode = '42501';
  end if;
  if (select count(*) from koz.duello where acan = u and olusturma >= gun_bas) >= 3 then
    raise exception 'gunluk_sinir' using errcode = '54000';
  end if;
  select array_agg(id) into secim from (
    select h.id from koz.duello_havuz h
    where not exists (select 1 from koz.duello d where (d.acan in (u, r) or d.rakip in (u, r)) and h.id = any(d.eller))
    order by random() limit p_el) x;
  if coalesce(cardinality(secim), 0) < p_el then raise exception 'havuz_bitti' using errcode = 'P0001'; end if;
  insert into koz.duello (acan, rakip, eller) values (u, r, secim) returning id into yeni;
  return yeni;
end $$;

revoke all on function public.koz_arkadas_sil(text), public.koz_kod_yenile() from public, anon;
grant execute on function public.koz_arkadas_sil(text), public.koz_kod_yenile() to authenticated;
