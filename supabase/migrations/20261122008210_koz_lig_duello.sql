-- Göç 8210: Koz Hesabı lig ayarı, arkadaşlık ve düello, silme (KH-15, KH-16; Koz oturumunun tanımı, 22 Kasım).
-- Lig: kademeler kart sırası (Onlu → As), 20 kişilik grup, haftanın en iyi 5 günü, eşitlikte ikincil (aktif süre).
-- Arkadaşlık sıralamaya katılım şartlarını değiştirmez (ad_gerekli, misafir kuralı aynen). RPC'ler yalnız kalıcı hesaba
-- açık; kimlik dönmez. Düello eli cevaplı havuzdan servis rolüyle okunur (dogrula-koz, ortak.denemeler anahtarı
-- "D:<duello>:<sira>", ilk sonucun puanı durum -> 'ilk' -> 'puan'). Şikâyet ortak hesap.sikayetEt'ten.

update ortak.oyunlar set ayarlar = ayarlar
  || '{"lig":{"kademeler":["Onlu","Vale","Kız","Papaz","As"],"grup_boyu":20,"cikis_orani":0.2,"inis_orani":0.2,"en_iyi_gun":5,"esitlik":"ikincil","bant_genisligi":0}}'::jsonb
  || jsonb_build_object('hesap', coalesce(ayarlar -> 'hesap', '{}'::jsonb) || '{"silme_fonksiyonu":"koz.oyuncu_verisini_sil"}'::jsonb)
 where id = 'koz';

create table koz.arkadas_kodu (
  kullanici uuid primary key references auth.users on delete cascade,
  kod text not null unique check (kod ~ '^[ACDEFGHJKMNPRTUVWXY34679]{8}$')
);
create table koz.arkadaslik (
  kullanici uuid not null references auth.users on delete cascade,
  arkadas uuid not null references auth.users on delete cascade,
  olusturma timestamptz not null default now(),
  primary key (kullanici, arkadas),
  check (kullanici <> arkadas)
);
create table koz.duello_havuz (id text primary key, kayit jsonb not null);
create table koz.duello (
  id uuid primary key default gen_random_uuid(),
  acan uuid not null references auth.users on delete cascade,
  rakip uuid not null references auth.users on delete cascade,
  eller text[] not null check (cardinality(eller) in (3, 5)),
  olusturma timestamptz not null default now()
);
create index on koz.duello (acan, olusturma desc);
create index on koz.duello (rakip, olusturma desc);
alter table koz.arkadas_kodu enable row level security;
alter table koz.arkadaslik enable row level security;
alter table koz.duello_havuz enable row level security;
alter table koz.duello enable row level security;
revoke all on koz.arkadas_kodu, koz.arkadaslik, koz.duello_havuz, koz.duello from public, anon, authenticated;
grant all on koz.arkadas_kodu, koz.arkadaslik, koz.duello_havuz, koz.duello to service_role;

create function koz.kalici_kim() returns uuid language plpgsql stable set search_path = '' as $$
declare u uuid := ortak.kim();
begin
  if u is null or ortak.anonim() then raise exception 'kalici_hesap_gerekli' using errcode = '42501'; end if;
  return u;
end $$;

create function public.koz_kodum() returns text language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim(); k text; harf constant text := 'ACDEFGHJKMNPRTUVWXY34679';
begin
  select kod into k from koz.arkadas_kodu where kullanici = u;
  while k is null loop
    k := (select string_agg(substr(harf, 1 + floor(random() * length(harf))::int, 1), '') from generate_series(1, 8));
    begin
      insert into koz.arkadas_kodu (kullanici, kod) values (u, k);
    exception when unique_violation then
      select kod into k from koz.arkadas_kodu where kullanici = u; -- yarışta öbür isteğin kodu; yoksa yeniden üretilir
    end;
  end loop;
  return k;
end $$;

create function public.koz_arkadas_ekle(p_kod text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim(); a uuid;
begin
  if not ortak.hiz_siniri('koz-ark:' || u, 20, 3600) then raise exception 'cok_istek' using errcode = '54000'; end if;
  select kullanici into a from koz.arkadas_kodu where kod = upper(trim(p_kod));
  if a is null then return jsonb_build_object('hata', 'kod_yok'); end if;
  if a = u then return jsonb_build_object('hata', 'kendin'); end if;
  if (select count(*) from koz.arkadaslik where kullanici = u) >= 100 then return jsonb_build_object('hata', 'sinir'); end if;
  insert into koz.arkadaslik (kullanici, arkadas) values (u, a), (a, u) on conflict do nothing;
  return jsonb_build_object('tamam', true);
end $$;

create function public.koz_arkadaslar() returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim();
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('ad', o.ad) order by o.ad), '[]'::jsonb)
          from koz.arkadaslik r left join ortak.oyuncular o on o.oyun_id = 'koz' and o.kullanici_id = r.arkadas
          where r.kullanici = u);
end $$;

create function public.koz_arkadas_tablosu(p_gun date) returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim();
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('ad', o.ad, 'puan', s.puan, 'ikincil', s.ikincil, 'ben', s.kullanici_id = u)
                                    order by s.puan desc, s.ikincil asc nulls last), '[]'::jsonb)
          from ortak.skorlar s
          join ortak.oyuncular o on o.oyun_id = 'koz' and o.kullanici_id = s.kullanici_id and o.ad is not null
          where s.oyun_id = 'koz' and s.tur = 'gunluk' and s.donem = p_gun::text
            and (s.kullanici_id = u or s.kullanici_id in (select arkadas from koz.arkadaslik where kullanici = u)));
end $$;

create function public.koz_duello_ac(p_kod text, p_el int) returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim(); r uuid; secim text[]; yeni uuid;
  gun_bas timestamptz := (ortak.bugun())::timestamp at time zone 'Europe/Istanbul';
begin
  if p_el not in (3, 5) then raise exception 'el_sayisi' using errcode = '22023'; end if;
  select kullanici into r from koz.arkadas_kodu where kod = upper(trim(p_kod));
  if r is null or not exists (select 1 from koz.arkadaslik where kullanici = u and arkadas = r) then
    raise exception 'arkadas_degil' using errcode = '42501';
  end if;
  select array_agg(id) into secim from (
    select h.id from koz.duello_havuz h
    where not exists (select 1 from koz.duello d where (d.acan in (u, r) or d.rakip in (u, r)) and h.id = any(d.eller))
    order by random() limit p_el) x;
  if coalesce(cardinality(secim), 0) < p_el then raise exception 'havuz_bitti' using errcode = 'P0001'; end if;
  insert into koz.duello (acan, rakip, eller)
    select u, r, secim where (select count(*) from koz.duello where acan = u and olusturma >= gun_bas) < 3
    returning id into yeni;
  if yeni is null then raise exception 'gunluk_sinir' using errcode = '54000'; end if;
  return yeni;
end $$;

create function public.koz_duellolar() returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim();
begin
  return (select coalesce(jsonb_agg(x order by x.olusturma desc), '[]'::jsonb) from (
    select d.id, d.olusturma, cardinality(d.eller) as el,
      (select o.ad from ortak.oyuncular o where o.oyun_id = 'koz' and o.kullanici_id = case when d.acan = u then d.rakip else d.acan end) as karsi,
      (select jsonb_agg(jsonb_build_object(
          'ben', (select dn.durum -> 'ilk' -> 'puan' from ortak.denemeler dn
                  where dn.oyun_id = 'koz' and dn.kullanici_id = u and dn.anahtar = 'D:' || d.id || ':' || i),
          'karsi', (select dn.durum -> 'ilk' -> 'puan' from ortak.denemeler dn
                    where dn.oyun_id = 'koz' and dn.kullanici_id = case when d.acan = u then d.rakip else d.acan end
                      and dn.anahtar = 'D:' || d.id || ':' || i)) order by i)
       from generate_series(1, cardinality(d.eller)) i) as puanlar
    from koz.duello d where d.acan = u or d.rakip = u
    order by d.olusturma desc limit 50) x);
end $$;

create function koz.oyuncu_verisini_sil(p uuid) returns void language sql security definer set search_path = '' as $$
  delete from koz.arkadas_kodu where kullanici = p;
  delete from koz.arkadaslik where kullanici = p or arkadas = p;
  delete from koz.duello where acan = p or rakip = p;
$$;

-- Düello havuzu yükleme (servis rolü): [{id, kayit}]; var olan güncellenir. Dönüş: yazılan satır sayısı.
create function public.koz_duello_havuz_yukle(p_satirlar jsonb) returns integer language sql security definer set search_path = '' as $$
  with y as (
    insert into koz.duello_havuz (id, kayit) select x ->> 'id', x -> 'kayit' from jsonb_array_elements(p_satirlar) x
    on conflict (id) do update set kayit = excluded.kayit returning 1
  ) select count(*)::int from y
$$;

revoke all on function koz.kalici_kim(), koz.oyuncu_verisini_sil(uuid), public.koz_duello_havuz_yukle(jsonb) from public, anon, authenticated;
grant execute on function koz.kalici_kim() to authenticated, service_role;
grant execute on function koz.oyuncu_verisini_sil(uuid), public.koz_duello_havuz_yukle(jsonb) to service_role;
revoke all on function public.koz_kodum(), public.koz_arkadas_ekle(text), public.koz_arkadaslar(), public.koz_arkadas_tablosu(date),
  public.koz_duello_ac(text, int), public.koz_duellolar() from public, anon;
grant execute on function public.koz_kodum(), public.koz_arkadas_ekle(text), public.koz_arkadaslar(), public.koz_arkadas_tablosu(date),
  public.koz_duello_ac(text, int), public.koz_duellolar() to authenticated;
