-- Göç 8570 (ORT-ARK, BG-12/RZ-9; kurucu kararı 27 Kasım, ADIL_PUAN §0.3–0.4).
-- 1) Lig grubu en çok 30 kişi (varsayılan 30; 30'dan büyük ayarlar 30'a iner; yeni atamalardan geçerli).
-- 2) Benzer etkinlik eşleşmesi: grup anahtarına etkinlik kademesi eklenir (önceki 7 günde oynanan gün: 0–2, 3–5, 6–7).
--    ayarlar.lig.etkinlik_esles = false ile kapatılır. Kapanışta eşitlerin hepsi terfi eder (rank; zaten böyleydi, testli).
-- 3) Alt oyun skoru: skorlar.tur 'alt' (donem '<gün>:<alt_id>[:<kip>]'). lig_durumu(oyun, p_alt) grubun aynı üyelerini
--    yalnız o alt oyunun en iyi N gün lig puanıyla sıralar (hesap anlık, saklanmaz; grup ve kademe değişmez).
-- 4) Arkadaş tablosu: oyun başına arkadaş kodu, karşılıklı arkadaşlık (kod bilen ekler, en çok 100), arkadas_tablosu.
--    Oyuncu satırı (oyuncular) silinince arkadaşlıkları da silinir. Misafir arkadaş ekleyemez ve tabloya girmez.

-- ---------------------------------------------------------------- 1, 2) lig grubu boyu ve etkinlik

update ortak.oyunlar set ayarlar = jsonb_set(ayarlar, '{lig,grup_boyu}', '30')
  where ayarlar ? 'lig' and coalesce((ayarlar -> 'lig' ->> 'grup_boyu')::int, 50) > 30;

alter table ortak.lig_gruplari add column etkinlik smallint not null default 0;
drop index ortak.lig_gruplari_acik;
create index lig_gruplari_acik on ortak.lig_gruplari (oyun_id, hafta, kademe, bant, etkinlik) where not kapandi;

-- Önceki 7 günde günlük skoru olan gün sayısından kademe: 0 (0–2 gün), 1 (3–5), 2 (6–7).
create function ortak.etkinlik_kademesi(p_oyun text, p_kullanici uuid, p_hafta date) returns smallint
language sql stable security definer set search_path = '' as $$
  select case when n >= 6 then 2 when n >= 3 then 1 else 0 end::smallint from (
    select count(*) n from ortak.skorlar s
    where s.oyun_id = p_oyun and s.kullanici_id = p_kullanici and s.tur = 'gunluk'
      and s.donem between (p_hafta - 7)::text and (p_hafta - 1)::text) x
$$;

create or replace function ortak.lig_ata(p_oyun text, p_kullanici uuid, p_hafta date) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  a jsonb;
  o ortak.oyuncular;
  v_bant integer;
  v_etk smallint := 0;
  boy integer;
  g bigint;
begin
  select grup_id into g from ortak.lig_uyeleri where oyun_id = p_oyun and hafta = p_hafta and kullanici_id = p_kullanici;
  if g is not null then return g; end if;

  select ayarlar -> 'lig' into a from ortak.oyunlar where id = p_oyun;
  if a is null then return null; end if;
  select * into o from ortak.oyuncular where oyun_id = p_oyun and kullanici_id = p_kullanici;
  v_bant := case when coalesce((a ->> 'bant_genisligi')::int, 0) > 0
                 then coalesce(o.seviye_puani, 0) / (a ->> 'bant_genisligi')::int else 0 end;
  if coalesce((a ->> 'etkinlik_esles')::boolean, true) then
    v_etk := ortak.etkinlik_kademesi(p_oyun, p_kullanici, p_hafta);
  end if;
  boy := least(coalesce((a ->> 'grup_boyu')::int, 30), 30);

  perform pg_advisory_xact_lock(hashtextextended(p_oyun || '|' || p_hafta || '|' || coalesce(o.kademe, 0) || '|' || v_bant || '|' || v_etk, 0));

  select gr.id into g from ortak.lig_gruplari gr
  where gr.oyun_id = p_oyun and gr.hafta = p_hafta and gr.kademe = coalesce(o.kademe, 0) and gr.bant = v_bant
    and gr.etkinlik = v_etk and not gr.kapandi
  order by gr.id desc limit 1;
  if g is not null and (select count(*) from ortak.lig_uyeleri u where u.grup_id = g) >= boy then g := null; end if;
  if g is null then
    insert into ortak.lig_gruplari (oyun_id, hafta, kademe, bant, etkinlik)
    values (p_oyun, p_hafta, coalesce(o.kademe, 0), v_bant, v_etk) returning id into g;
  end if;
  insert into ortak.lig_uyeleri (grup_id, oyun_id, hafta, kullanici_id) values (g, p_oyun, p_hafta, p_kullanici);
  return g;
end $$;

-- ---------------------------------------------------------------- 3) alt oyun skoru ve süzülmüş lig

alter table ortak.skorlar drop constraint skorlar_tur_check;
alter table ortak.skorlar add constraint skorlar_tur_check check (tur in ('gunluk', 'etkinlik', 'alt'));
alter table ortak.skorlar add constraint skorlar_alt_donem check (tur <> 'alt' or donem ~ '^\d{4}-\d{2}-\d{2}:[a-z0-9_]{1,32}(:[a-z0-9_]{1,16})?$');

-- p_alt verilirse: grubun üyeleri yalnız o alt oyunun 'alt' skorlarından (kipsiz ya da kip 'kesif') haftanın en iyi
-- en_iyi_gun günü toplamıyla sıralanır. Kip ayrımı: Keşif lige girer, Yarış girmez (BG ve Remzle kararı); kip yoksa girer.
create function ortak.lig_durumu(p_oyun text, p_alt text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  u uuid := ortak.kim();
  v_hafta date := ortak.iso_hafta(ortak.bugun());
  a jsonb;
  n int;
  g bigint;
  r jsonb := ortak.lig_durumu(p_oyun);
  uyeler jsonb;
begin
  if p_alt is null then return r; end if;
  if p_alt !~ '^[a-z0-9_]{1,32}$' then raise exception 'alt_gecersiz'; end if;
  select ayarlar -> 'lig' into a from ortak.oyunlar where id = p_oyun;
  n := coalesce((a ->> 'en_iyi_gun')::int, 5);
  select grup_id into g from ortak.lig_uyeleri where oyun_id = p_oyun and hafta = v_hafta and kullanici_id = u;
  if g is not null then
    select jsonb_agg(jsonb_build_object('sira', x.sira, 'ad', x.ad, 'puan', x.puan, 'ikincil', x.ikincil, 'profil', x.profil, 'ben', x.ben) order by x.sira, x.ad)
    into uyeler from (
      select rank() over (order by t.puan desc,
               case when coalesce(a ->> 'esitlik', 'ortak') = 'ikincil' then t.ikincil end asc nulls last) as sira,
             oy.ad, oy.profil_id as profil, t.puan,
             case when coalesce(a ->> 'esitlik', 'ortak') = 'ikincil' then t.ikincil end as ikincil,
             t.kullanici_id = u as ben
      from (
        select l.kullanici_id,
               coalesce((select sum(z.lig_puani) from (
                  select s.lig_puani from ortak.skorlar s
                  where s.oyun_id = p_oyun and s.kullanici_id = l.kullanici_id and s.tur = 'alt'
                    and split_part(s.donem, ':', 2) = p_alt and split_part(s.donem, ':', 3) in ('', 'kesif')
                    and left(s.donem, 10) between v_hafta::text and (v_hafta + 6)::text
                    and s.lig_puani is not null and not ('nabiz_boslugu' = any (s.bayraklar))
                  order by s.lig_puani desc, s.ikincil asc nulls last limit n) z), 0) as puan,
               coalesce((select sum(z.ikincil) from (
                  select coalesce(s.ikincil, 0) ikincil from ortak.skorlar s
                  where s.oyun_id = p_oyun and s.kullanici_id = l.kullanici_id and s.tur = 'alt'
                    and split_part(s.donem, ':', 2) = p_alt and split_part(s.donem, ':', 3) in ('', 'kesif')
                    and left(s.donem, 10) between v_hafta::text and (v_hafta + 6)::text
                    and s.lig_puani is not null and not ('nabiz_boslugu' = any (s.bayraklar))
                  order by s.lig_puani desc, s.ikincil asc nulls last limit n) z), 0) as ikincil
        from ortak.lig_uyeleri l where l.grup_id = g) t
      left join ortak.oyuncular oy on oy.oyun_id = p_oyun and oy.kullanici_id = t.kullanici_id) x;
  end if;
  return r || jsonb_build_object('alt', p_alt, 'uyeler', coalesce(uyeler, '[]'::jsonb));
end $$;
revoke execute on function ortak.lig_durumu(text, text) from public, anon;
grant execute on function ortak.lig_durumu(text, text) to authenticated;

-- ---------------------------------------------------------------- 4) arkadaş tablosu

create table ortak.arkadas_kodlari (
  oyun_id text not null,
  kullanici_id uuid not null,
  kod text not null unique check (kod ~ '^[A-HJ-NP-Z2-9]{6}$'),
  primary key (oyun_id, kullanici_id),
  foreign key (oyun_id, kullanici_id) references ortak.oyuncular on delete cascade
);
alter table ortak.arkadas_kodlari enable row level security;

-- Her arkadaşlık iki satır (a→b ve b→a): sorgu tek yönlü, silme iki yönlü.
create table ortak.arkadasliklar (
  oyun_id text not null,
  kullanici_id uuid not null,
  arkadas_id uuid not null,
  olusturma timestamptz not null default now(),
  primary key (oyun_id, kullanici_id, arkadas_id),
  check (kullanici_id <> arkadas_id),
  foreign key (oyun_id, kullanici_id) references ortak.oyuncular on delete cascade,
  foreign key (oyun_id, arkadas_id) references ortak.oyuncular on delete cascade
);
create index arkadasliklar_arkadas on ortak.arkadasliklar (oyun_id, arkadas_id);
alter table ortak.arkadasliklar enable row level security;
revoke all on ortak.arkadas_kodlari, ortak.arkadasliklar from public, anon, authenticated;

-- Kalıcı hesap ve oyunda adı olan oyuncu şartı (sıralamadaki kuralla aynı).
create function ortak.arkadas_sart(p_oyun text) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare u uuid := ortak.kim();
begin
  if ortak.anonim() then raise exception 'hesap_gerekli' using errcode = '28000'; end if;
  if not exists (select 1 from ortak.oyuncular o where o.oyun_id = p_oyun and o.kullanici_id = u
                 and o.ad is not null and not o.ad_otomatik) then
    raise exception 'ad_gerekli';
  end if;
  return u;
end $$;

-- Kendi kodu (yoksa üretir). Karışan harfler yok (I, O, 0, 1).
create function ortak.arkadas_kodum(p_oyun text) returns text
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.arkadas_sart(p_oyun); k text;
begin
  select kod into k from ortak.arkadas_kodlari where oyun_id = p_oyun and kullanici_id = u;
  while k is null loop
    k := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '') from generate_series(1, 6));
    begin
      insert into ortak.arkadas_kodlari (oyun_id, kullanici_id, kod) values (p_oyun, u, k);
    exception when unique_violation then k := null;
    end;
  end loop;
  return k;
end $$;

-- Kodla ekleme: karşılıklı. Dakikada 20 deneme (kod tahmini), en çok 100 arkadaş. Dönen: arkadaşın adı ve profil kimliği.
create function ortak.arkadas_ekle(p_oyun text, p_kod text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.arkadas_sart(p_oyun); b uuid; o ortak.oyuncular;
begin
  if not ortak.hiz_siniri('arkadas:' || u, 20, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  select kullanici_id into b from ortak.arkadas_kodlari where oyun_id = p_oyun and kod = upper(btrim(p_kod));
  if b is null then raise exception 'kod_yok'; end if;
  if b = u then raise exception 'kendi_kodun'; end if;
  if not exists (select 1 from ortak.arkadasliklar where oyun_id = p_oyun and kullanici_id = u and arkadas_id = b) then
    if (select count(*) from ortak.arkadasliklar where oyun_id = p_oyun and kullanici_id = u) >= 100
       or (select count(*) from ortak.arkadasliklar where oyun_id = p_oyun and kullanici_id = b) >= 100 then
      raise exception 'arkadas_siniri';
    end if;
    insert into ortak.arkadasliklar (oyun_id, kullanici_id, arkadas_id) values (p_oyun, u, b), (p_oyun, b, u)
      on conflict do nothing;
  end if;
  select * into o from ortak.oyuncular where oyun_id = p_oyun and kullanici_id = b;
  return jsonb_build_object('ad', o.ad, 'profil', o.profil_id);
end $$;

-- Çıkarma profil kimliğiyle (istemci kullanıcı kimliği görmez); iki yönden de silinir.
create function ortak.arkadas_cikar(p_oyun text, p_profil uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); b uuid;
begin
  select kullanici_id into b from ortak.oyuncular where oyun_id = p_oyun and profil_id = p_profil;
  delete from ortak.arkadasliklar where oyun_id = p_oyun
    and ((kullanici_id = u and arkadas_id = b) or (kullanici_id = b and arkadas_id = u));
end $$;

-- Arkadaş tablosu: oyuncu ve arkadaşları. p_tur 'gunluk' | 'etkinlik' | 'alt' (skorlar, oyunun sıralama yönü ve eşitliği)
-- ya da 'hafta' (p_donem = hafta başı; haftalık lig puanı). Skoru olmayan arkadaş puansız, sıranın sonunda.
create function ortak.arkadas_tablosu(p_oyun text, p_tur text, p_donem text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := ortak.kim();
  a jsonb;
  ikincilli boolean;
begin
  if not ortak.hiz_siniri('arkadas_tablo:' || u, 60, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  if p_tur not in ('gunluk', 'etkinlik', 'alt', 'hafta') then raise exception 'tur_gecersiz'; end if;
  select coalesce(ayarlar -> 'siralama', '{}') into a from ortak.oyunlar where id = p_oyun;
  if not found then raise exception 'oyun_yok'; end if;
  ikincilli := coalesce(a ->> 'esitlik', 'ortak') = 'ikincil';
  return jsonb_build_object('satirlar', coalesce((
    select jsonb_agg(jsonb_build_object('sira', x.sira, 'ad', x.ad, 'puan', x.puan, 'ikincil', x.ikincil, 'profil', x.profil, 'ben', x.ben)
                     order by x.sira nulls last, x.ad)
    from (
      select case when k.deger is not null then rank() over (order by k.deger desc nulls last,
                    case when ikincilli then k.ikincil end asc nulls last) end::int as sira,
             o.ad, o.profil_id as profil, k.puan, case when ikincilli then k.ikincil end as ikincil, k.kim = u as ben
      from (
        select kim.id as kim,
               case when p_tur = 'hafta' then l.puan else s.puan end as puan,
               case when p_tur = 'hafta' then l.puan else s.sira_degeri end as deger,
               case when p_tur = 'hafta' then l.ikincil else s.ikincil end as ikincil
        from (select u as id union select arkadas_id from ortak.arkadasliklar where oyun_id = p_oyun and kullanici_id = u) kim
        left join ortak.skorlar s on p_tur <> 'hafta' and s.oyun_id = p_oyun and s.tur = p_tur and s.donem = p_donem and s.kullanici_id = kim.id
        left join ortak.lig_uyeleri l on p_tur = 'hafta' and l.oyun_id = p_oyun and l.hafta::text = p_donem and l.kullanici_id = kim.id
      ) k
      join ortak.oyuncular o on o.oyun_id = p_oyun and o.kullanici_id = k.kim
    ) x), '[]'::jsonb));
end $$;

revoke execute on function ortak.etkinlik_kademesi(text, uuid, date), ortak.arkadas_sart(text),
  ortak.arkadas_kodum(text), ortak.arkadas_ekle(text, text), ortak.arkadas_cikar(text, uuid), ortak.arkadas_tablosu(text, text, text)
  from public, anon;
grant execute on function ortak.arkadas_kodum(text), ortak.arkadas_ekle(text, text), ortak.arkadas_cikar(text, uuid),
  ortak.arkadas_tablosu(text, text, text) to authenticated;
revoke execute on function ortak.etkinlik_kademesi(text, uuid, date), ortak.arkadas_sart(text) from authenticated;
