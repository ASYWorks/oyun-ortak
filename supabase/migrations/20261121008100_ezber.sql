-- Göç 8100: Ezber Bozan oyun-ortak'a geçiyor (Neon olay deposu ve Vercel /tmp bırakılıyor; kalıcı veri yok).
-- Sözleşme: ezber-bozan/docs/DOGRULA_SOZLESME.md (dogrula-ezber, oyunun deposunda). Kararlar ISTEKLER.md EZ-1..EZ-5.
-- Oyun kimliği 'ezber' (oyuncuya görünmez; ad değişse de değişmez).
-- - ortak.oyunlar 'ezber': ortak ad kuralı, günlük sıralama (büyük puan önde, eşitlikte ikincil = süre, küçük önde); lig yok.
-- - ezber.gunluk: günün perdesi. Gizli veri yok (istemci oyunu yerelde bitirir, sunucu hamleleri yeniden oynatır); yalnız
--   ilk_hamle (ipucu 3) ve aile (ipucu sayılır, teslimden sonra döner) istemciye baştan gitmez. Açılmış gün değişemez.
-- - ezber.ipucu: kullanıcının o gün aldığı ipucu basamakları (hak sunucuda). Basamak sırayla alınır. 3. basamak "yardımlı":
--   dogrula-ezber o günün skorunu sıralamaya yazmaz (ortak.skor_yaz çağrılmaz), böylece sıralama ve ligden dışlanır.
-- - Ürün: ezber_tam_acilim → hak tam_acilim (süresiz, aile paylaşımı RevenueCat'te).

create schema if not exists ezber;
grant usage on schema ezber to service_role;
alter default privileges in schema ezber revoke all on tables from anon, authenticated, public;
alter default privileges in schema ezber revoke execute on functions from anon, authenticated, public;
alter default privileges in schema ezber grant all on tables to service_role;

insert into ortak.oyunlar (id, ad, ayarlar) values (
  'ezber', 'Ezber Bozan', '{
    "ad": { "en_az": 3, "en_cok": 20, "degistirme_gun": 30 },
    "hesap": { "silme_fonksiyonu": "ezber.oyuncu_verisini_sil" },
    "siralama": { "esitlik": "ikincil", "dagilim_esigi": 50 },
    "odeme": { "revenuecat_uygulamalari": [] }
  }'
) on conflict (id) do nothing;
insert into ortak.urunler (urun, oyun_id, hak) values ('ezber_tam_acilim', 'ezber', 'tam_acilim') on conflict do nothing;

create table ezber.gunluk (
  gun date primary key,
  challenge_id text not null unique,
  bulmaca jsonb not null,          -- BulmacaTanimi (istemciye gider)
  en_kisa integer not null check (en_kisa > 0),
  ilk_hamle jsonb not null,        -- ipucu 3 (istemciye baştan gitmez)
  hedef_beklenti jsonb,            -- ipucu 2 (içerik 1.0.1'e kadar boş)
  aile text not null,              -- teslim yanıtında döner
  kaynak_sinif text not null,
  icerik_surumu text not null,
  motor_surumu text not null,
  yukleme timestamptz not null default now()
);
alter table ezber.gunluk enable row level security; -- politika yok: yalnız servis rolü
revoke all on ezber.gunluk from public, anon, authenticated;
grant all on ezber.gunluk to service_role;

create function ezber.acilmis_gun_koru() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.gun <= ortak.bugun() and coalesce(current_setting('ezber.duzeltme', true), '') <> 'evet'
     and (tg_op = 'DELETE' or (old.challenge_id, old.bulmaca, old.en_kisa, old.ilk_hamle, old.hedef_beklenti, old.aile)
                              is distinct from (new.challenge_id, new.bulmaca, new.en_kisa, new.ilk_hamle, new.hedef_beklenti, new.aile)) then
    raise exception 'acilmis_gun_degisemez' using errcode = 'P0001',
      hint = 'Bilinçli düzeltme: aynı oturumda set ezber.duzeltme = ''evet''; değişiklik yönetim kaydına düşer.';
  end if;
  return coalesce(new, old);
end $$;
create trigger acilmis_gun_koru before update or delete on ezber.gunluk for each row execute function ezber.acilmis_gun_koru();
create trigger yonetim_kaydi after insert or update or delete on ezber.gunluk for each row execute function ortak.yonetim_kaydet('gun');

create table ezber.ipucu (
  kullanici_id uuid not null references auth.users on delete cascade,
  gun date not null,
  basamak smallint not null check (basamak between 1 and 3),
  zaman timestamptz not null default now(),
  primary key (kullanici_id, gun, basamak)
);
alter table ezber.ipucu enable row level security;
revoke all on ezber.ipucu from public, anon, authenticated;
grant all on ezber.ipucu to service_role;
create index ipucu_gun on ezber.ipucu (gun);

-- "Bu oyundaki verimi sil": ortak silme yolu çağırır.
create function ezber.oyuncu_verisini_sil(u uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from ezber.ipucu where kullanici_id = u;
end $$;
revoke all on function ezber.oyuncu_verisini_sil(uuid) from public, anon, authenticated;

-- dogrula-ezber (servis rolü): günün satırı ya da null.
create function public.ezber_gunluk_oku(p_gun date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select to_jsonb(g) - 'yukleme' from ezber.gunluk g where g.gun = p_gun
$$;

-- İpucu hakkı (servis rolü): p_basamak verilirse alır (sırayla: n için n−1 alınmış olmalı; aynı basamak yeniden
-- istenirse hata değil, aynı sonuç). Dönüş: alınmış basamaklar dizisi, artan. Sıra dışı istek: 'ipucu_sirasi' hatası.
create function public.ezber_ipucu(p_kullanici uuid, p_gun date, p_basamak smallint default null) returns smallint[]
language plpgsql security definer set search_path = '' as $$
begin
  if p_basamak is not null then
    if p_basamak > 1 and not exists (select 1 from ezber.ipucu where kullanici_id = p_kullanici and gun = p_gun and basamak = p_basamak - 1) then
      raise exception 'ipucu_sirasi' using errcode = '22023';
    end if;
    insert into ezber.ipucu (kullanici_id, gun, basamak) values (p_kullanici, p_gun, p_basamak) on conflict do nothing;
  end if;
  return coalesce((select array_agg(basamak order by basamak) from ezber.ipucu where kullanici_id = p_kullanici and gun = p_gun), '{}');
end $$;

-- Yükleme (servis rolü): [{gun, challenge_id, bulmaca, en_kisa, ilk_hamle, hedef_beklenti, aile, kaynak_sinif, motor_surumu}]
-- ve içerik sürümü. Eksik gün eklenir; var olan yalnız gelecek günde ve içerik sürümü farklıysa güncellenir.
-- Dönüş: { yazilan, atlanan, son_gun, kalan_gun }.
create function public.ezber_gunluk_yukle(p_satirlar jsonb, p_surum text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare yazilan int; toplam int := jsonb_array_length(p_satirlar);
begin
  with girdi as (
    select (x ->> 'gun')::date as gun, x ->> 'challenge_id' as challenge_id, x -> 'bulmaca' as bulmaca, (x ->> 'en_kisa')::int as en_kisa,
           x -> 'ilk_hamle' as ilk_hamle, nullif(x -> 'hedef_beklenti', 'null'::jsonb) as hedef_beklenti, x ->> 'aile' as aile,
           x ->> 'kaynak_sinif' as kaynak_sinif, x ->> 'motor_surumu' as motor_surumu
    from jsonb_array_elements(p_satirlar) x
  ), yaz as (
    insert into ezber.gunluk as g (gun, challenge_id, bulmaca, en_kisa, ilk_hamle, hedef_beklenti, aile, kaynak_sinif, icerik_surumu, motor_surumu)
    select gun, challenge_id, bulmaca, en_kisa, ilk_hamle, hedef_beklenti, aile, kaynak_sinif, p_surum, motor_surumu from girdi
    on conflict (gun) do update set challenge_id = excluded.challenge_id, bulmaca = excluded.bulmaca, en_kisa = excluded.en_kisa,
      ilk_hamle = excluded.ilk_hamle, hedef_beklenti = excluded.hedef_beklenti, aile = excluded.aile, kaynak_sinif = excluded.kaynak_sinif,
      icerik_surumu = excluded.icerik_surumu, motor_surumu = excluded.motor_surumu, yukleme = now()
      where g.gun > ortak.bugun() and g.icerik_surumu is distinct from excluded.icerik_surumu
    returning 1
  ) select count(*) into yazilan from yaz;
  return jsonb_build_object('yazilan', yazilan, 'atlanan', toplam - yazilan,
    'son_gun', (select max(gun) from ezber.gunluk), 'kalan_gun', (select max(gun) - ortak.bugun() from ezber.gunluk));
end $$;

revoke all on function public.ezber_gunluk_oku(date), public.ezber_ipucu(uuid, date, smallint), public.ezber_gunluk_yukle(jsonb, text) from public, anon, authenticated;
grant execute on function public.ezber_gunluk_oku(date), public.ezber_ipucu(uuid, date, smallint), public.ezber_gunluk_yukle(jsonb, text) to service_role;
