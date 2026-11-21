-- Göç 7600: Halka ödülleri sunucuda (Halka hk23, halka-kelime 4e2e54f; kurucu kararı 21 Kasım "hata kalmasın").
-- Halka bölümü (hk23_odul_sunucu.sql) aynen; ortak bölüm: odul_kaydet, oyunun ayarlarındaki `sunucu_odulleri` öneklerindeki
-- ödülleri istemciden sessizce atlar (eski istemci kırılmaz). Halka: desen-, cerceve-, rozet-etkinlik-, rozet-usta-.
-- Bağlama ödülü kuralı (7300) aynen kalır.

-- HK-23 (Serdar 21 Kasım 2026, "hata kalmasın"): ödüller sunucuda (docs/inceleme/ODUL_SUNUCU.md). Göçü oyun-ortak uygular;
-- hk22'den ve oyun-ortak 20261120005100 (turnuva %5) ile 20261120007000'den (gonderim_bayraklar) sonra. Yalnız halka.* ve
-- public.halka_*. Testi: halka-kelime tests/sql.test.ts "hk23". Uygulanmadı.
--
-- 1) Etkinlik bulmacaları Usta altyapısında: halka.turnuva_bulmacalar kimliği `usta-YYYY-AA-GG` ya da `<etkinlik>-<n>`, yeni
--    sütun `etkinlik` (Usta için boş). Kontrol, ipucu, cevap, dosya, dogrula-halka okuması ve halka_gonderim_verisi (tur
--    'etkinlik', dönem = kimlik, deneme 'turnuva:'||kimlik) kimliğe bakmaz, değişmedi. turnuva_odul_ver yalnız `usta-%`.
-- 2) Sezon ve etkinlik ödülleri (desen, çerçeve, etkinlik rozeti, Usta rozeti) yalnız sunucunun gördüğü çözümden yazılır:
--    halka_odul_hesapla ve halka_etkinlik_cozum (dogrula-halka çağırır, yalnız servis rolü), kaynak = 'sunucu'.

-- ---------------------------------------------------------------- turnuva_bulmacalar: etkinlik bulmacaları

alter table halka.turnuva_bulmacalar drop constraint if exists turnuva_bulmacalar_kimlik_check;
alter table halka.turnuva_bulmacalar add constraint turnuva_bulmacalar_kimlik_check
  check (kimlik ~ '^usta-\d{4}-\d{2}-\d{2}$' or kimlik ~ '^[a-z0-9]+(-[a-z0-9]+)*-[1-9]$');
alter table halka.turnuva_bulmacalar add column if not exists etkinlik text;  -- etkinlik kimliği; Usta için boş

-- 20261120005100 gövdesi; yalnız Usta Turnuvası (etkinlik bulmacasının sıralama rozeti yok).
create or replace function halka.turnuva_odul_ver() returns integer
language plpgsql security definer set search_path = '' as $$
declare t record; n int := 0;
begin
  for t in select kimlik from halka.turnuva_bulmacalar
           where kimlik like 'usta-%' and halka.cevap_acik(bitir, now()) and bitir >= ortak.bugun() - 14 loop
    n := n + ortak.siralama_odulu_ver('halka', 'etkinlik', t.kimlik, 'sira:rozet-altin-' || t.kimlik, 0.05);
  end loop;
  return n;
end $$;
revoke execute on function halka.turnuva_odul_ver() from public, anon, authenticated;

-- hk21 gövdesi; + etkinlik.
create or replace function public.halka_turnuva_yukle(p_satirlar jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  insert into halka.turnuva_bulmacalar (kimlik, basla, bitir, halkalar, cevaplar, cozum, anlamlar, kilit_sirasi, ek, hedef, baslangic, kurallar, tema, zorluk, etkinlik)
  select x.kimlik, x.basla, x.bitir, x.halkalar, x.cevaplar, x.cozum, x.anlamlar, x.kilit_sirasi, x.ek, x.hedef, x.baslangic, x.kurallar, x.tema, x.zorluk, x.etkinlik
  from jsonb_to_recordset(p_satirlar) as x(kimlik text, basla date, bitir date, halkalar jsonb, cevaplar text[], cozum jsonb,
                                           anlamlar jsonb, kilit_sirasi integer[], ek jsonb, hedef integer, baslangic jsonb, kurallar jsonb, tema text, zorluk integer,
                                           etkinlik text)
  on conflict (kimlik) do update set basla = excluded.basla, bitir = excluded.bitir, halkalar = excluded.halkalar,
    cevaplar = excluded.cevaplar, cozum = excluded.cozum, anlamlar = excluded.anlamlar, kilit_sirasi = excluded.kilit_sirasi,
    ek = excluded.ek, hedef = excluded.hedef, baslangic = excluded.baslangic, kurallar = excluded.kurallar, tema = excluded.tema, zorluk = excluded.zorluk,
    etkinlik = excluded.etkinlik;
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------- tablolar (yalnız servis rolü)

create table if not exists halka.sezonlar (
  id text primary key,
  basla date not null,
  bitir date not null check (basla <= bitir),
  yarim text,                        -- yarim_esik günde: desen-<sezon>
  tam text,                          -- tam_esik günde: cerceve-<sezon>
  yarim_esik integer not null default 25,
  tam_esik integer not null default 50
);
create table if not exists halka.etkinlik_odulleri (
  etkinlik text primary key,
  odul text,                         -- desen-<etkinlik> ya da rozet-etkinlik-<id>
  hedef integer,                     -- gereken doğrulanmış çözüm
  basla date,
  bitir date
);
create table if not exists halka.etkinlik_cozumler (
  kullanici_id uuid not null references auth.users on delete cascade,
  kimlik text not null,
  etkinlik text not null,
  zaman timestamptz not null default now(),
  primary key (kullanici_id, kimlik)
);
alter table halka.sezonlar enable row level security;
alter table halka.etkinlik_odulleri enable row level security;
alter table halka.etkinlik_cozumler enable row level security;
revoke all on halka.sezonlar, halka.etkinlik_odulleri, halka.etkinlik_cozumler from public, anon, authenticated;
grant all on halka.sezonlar, halka.etkinlik_odulleri, halka.etkinlik_cozumler to service_role;

-- ---------------------------------------------------------------- yükleme (takvimden, scripts/upload_daily.ts)

create or replace function public.halka_odul_yukle(p_sezonlar jsonb, p_etkinlikler jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare n int; m int;
begin
  insert into halka.sezonlar (id, basla, bitir, yarim, tam, yarim_esik, tam_esik)
  select x.id, x.basla, x.bitir, x.yarim, x.tam, coalesce(x.yarim_esik, 25), coalesce(x.tam_esik, 50)
  from jsonb_to_recordset(coalesce(p_sezonlar, '[]')) as x(id text, basla date, bitir date, yarim text, tam text, yarim_esik integer, tam_esik integer)
  on conflict (id) do update set basla = excluded.basla, bitir = excluded.bitir, yarim = excluded.yarim, tam = excluded.tam,
    yarim_esik = excluded.yarim_esik, tam_esik = excluded.tam_esik;
  get diagnostics n = row_count;
  insert into halka.etkinlik_odulleri (etkinlik, odul, hedef, basla, bitir)
  select x.id, x.odul, x.hedef, x.basla, x.bitir
  from jsonb_to_recordset(coalesce(p_etkinlikler, '[]')) as x(id text, odul text, hedef integer, basla date, bitir date)
  on conflict (etkinlik) do update set odul = excluded.odul, hedef = excluded.hedef, basla = excluded.basla, bitir = excluded.bitir;
  get diagnostics m = row_count;
  return n + m;
end $$;

-- ---------------------------------------------------------------- ödül yazımı

-- Yeni yazılan ödülleri döndürür (var olan tekrar yazılmaz).
create or replace function halka.odul_yaz(p_kullanici uuid, p_oduller text[]) returns text[]
language sql set search_path = '' as $$
  with y as (
    insert into ortak.oduller (oyun_id, kullanici_id, odul, kaynak, kazanildi)
    select 'halka', p_kullanici, x, 'sunucu', now() from unnest(p_oduller) x
    on conflict do nothing returning odul)
  select coalesce(array_agg(odul order by odul), '{}') from y
$$;
revoke execute on function halka.odul_yaz(uuid, text[]) from public, anon, authenticated;

-- dogrula-halka gönderimden sonra çağırır. gunluk: sezondaki nabız boşluksuz farklı gün sayısı eşikleri geçince desen/çerçeve;
-- etkinlik usta-*: skor varsa rozet-usta-<gün>.
create or replace function public.halka_odul_hesapla(p_kullanici uuid, p_tur text, p_donem text) returns text[]
language plpgsql security definer set search_path = '' as $$
declare s halka.sezonlar; n int; aday text[] := '{}';
begin
  if p_tur = 'gunluk' then
    select * into s from halka.sezonlar where p_donem::date between basla and bitir order by basla desc limit 1;
    if found then
      select count(distinct k.donem) into n from ortak.skorlar k
       where k.oyun_id = 'halka' and k.kullanici_id = p_kullanici and k.tur = 'gunluk'
         and k.donem between s.basla::text and s.bitir::text and not ('nabiz_boslugu' = any(k.bayraklar));
      if s.yarim is not null and n >= s.yarim_esik then aday := aday || s.yarim; end if;
      if s.tam is not null and n >= s.tam_esik then aday := aday || s.tam; end if;
    end if;
  elsif p_tur = 'etkinlik' and p_donem like 'usta-%' and exists (
      select 1 from ortak.skorlar k where k.oyun_id = 'halka' and k.kullanici_id = p_kullanici and k.tur = 'etkinlik' and k.donem = p_donem) then
    aday := array['rozet-' || p_donem];
  end if;
  return halka.odul_yaz(p_kullanici, aday);
end $$;

-- dogrula-halka etkinlik bulmacası gönderiminden sonra çağırır. Pencere: başlangıçtan bitiş gününün İstanbul gece yarısından
-- 10 dk sonrasına (geç gönderim; halka.cevap_acik). Hedefe ulaşınca etkinliğin ödülü.
create or replace function public.halka_etkinlik_cozum(p_kullanici uuid, p_kimlik text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t record; o record; n int; yeni text[] := '{}';
begin
  select b.etkinlik, b.basla, b.bitir into t from halka.turnuva_bulmacalar b where b.kimlik = p_kimlik and b.etkinlik is not null;
  if not found then raise exception 'bulmaca_yok'; end if;
  if ortak.bugun() < t.basla or halka.cevap_acik(t.bitir, now()) then raise exception 'pencere'; end if;
  insert into halka.etkinlik_cozumler (kullanici_id, kimlik, etkinlik) values (p_kullanici, p_kimlik, t.etkinlik) on conflict do nothing;
  select count(*) into n from halka.etkinlik_cozumler c where c.kullanici_id = p_kullanici and c.etkinlik = t.etkinlik;
  select e.odul, e.hedef into o from halka.etkinlik_odulleri e where e.etkinlik = t.etkinlik;
  if o.odul is not null and n >= o.hedef then yeni := halka.odul_yaz(p_kullanici, array[o.odul]); end if;
  return jsonb_build_object('etkinlik', t.etkinlik, 'cozulen', n, 'hedef', o.hedef, 'oduller', to_jsonb(yeni));
end $$;

revoke execute on function public.halka_odul_yukle(jsonb, jsonb), public.halka_odul_hesapla(uuid, text, text),
  public.halka_etkinlik_cozum(uuid, text) from public, anon, authenticated;
grant execute on function public.halka_odul_yukle(jsonb, jsonb), public.halka_odul_hesapla(uuid, text, text),
  public.halka_etkinlik_cozum(uuid, text) to service_role;

-- ---------------------------------------------------------------- ortak: sunucu ödülleri istemciden yazılmaz
update ortak.oyunlar set ayarlar = jsonb_set(coalesce(ayarlar, '{}'), '{sunucu_odulleri}', '["desen-","cerceve-","rozet-etkinlik-","rozet-usta-"]')
where id = 'halka';

create or replace function ortak.odul_kaydet(p_oyun text, p_oduller jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); n integer; bag text; verildi text; onekler jsonb;
begin
  if ortak.anonim() then raise exception 'kalici_hesap_gerekli'; end if;
  if jsonb_typeof(p_oduller) <> 'array' or jsonb_array_length(p_oduller) > 100 then
    raise exception 'oduller_gecersiz';
  end if;
  if exists (select 1 from jsonb_array_elements(p_oduller) x where x ->> 'odul' like 'sira:%') then
    raise exception 'odul_yasak';
  end if;
  if not ortak.hiz_siniri('odul:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  if (select count(*) from ortak.oduller where oyun_id = p_oyun and kullanici_id = u)
     + jsonb_array_length(p_oduller) > 1000 then
    raise exception 'odul_tavan' using errcode = '54000';
  end if;
  select ayarlar -> 'hesap' ->> 'baglama_odulu', coalesce(ayarlar -> 'sunucu_odulleri', '[]') into bag, onekler
    from ortak.oyunlar where id = p_oyun;
  select baglama_odulu into verildi from ortak.oyuncular where oyun_id = p_oyun and kullanici_id = u;
  insert into ortak.oduller (oyun_id, kullanici_id, odul, kaynak, kazanildi)
    select p_oyun, u, x ->> 'odul', x ->> 'kaynak',
           least(coalesce((x ->> 'kazanildi')::timestamptz, now()), now())
    from jsonb_array_elements(p_oduller) x
    -- bağlama ödülü: yalnız sunucu verdiyse (önekli olsa da); diğerleri: sunucu öneklerinde değilse
    where case when x ->> 'odul' = bag then verildi is not distinct from bag
               else not exists (select 1 from jsonb_array_elements_text(onekler) o where starts_with(x ->> 'odul', o)) end
    on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
