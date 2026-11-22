-- Göç 8180: Mahalle Dönüşümü oyun-ortak'a geçiyor (Vercel'den; kendi sunucusu yoktu, canlıda veri yok). İstekler MD-1, MD-2.
-- Kurucu kararı 22 Kasım: puan ADIL_PUAN'a geçer (kutu başına 0–100, sunucu süresi eşitlik bozucu). Günün Beşlisi:
-- günde 5 kutu, hesapla; deneme durumu ortak.denemeler'de (dogrula-mahalle, oyunun deposunda). Lig ayarı kademe adları
-- kesinleşince ayrı göçle eklenir. Oyuna özgü kullanıcı tablosu yok: ortak silme yolu yeter.
-- - mahalle.gunluk: günün beş kutusu, cevaplar ve açıklamalarla, yalnız sunucuda. Açılmış gün (bugün ve öncesi)
--   değişemez, silinemez; bilinçli düzeltme `set mahalle.duzeltme = 'evet'`.

create schema if not exists mahalle;
grant usage on schema mahalle to service_role;
alter default privileges in schema mahalle revoke all on tables from anon, authenticated, public;
alter default privileges in schema mahalle revoke execute on functions from anon, authenticated, public;
alter default privileges in schema mahalle grant all on tables to service_role;

insert into ortak.oyunlar (id, ad, ayarlar) values (
  'mahalle', 'Mahalle Dönüşümü', '{
    "ad": { "en_az": 3, "en_cok": 20, "degistirme_gun": 30 },
    "siralama": { "esitlik": "ikincil", "dagilim_esigi": 50 },
    "odeme": { "revenuecat_uygulamalari": [] }
  }'
) on conflict (id) do nothing;

create table mahalle.gunluk (
  gun date primary key,
  kutular jsonb not null check (jsonb_typeof(kutular) = 'array' and jsonb_array_length(kutular) = 5),
  icerik_surumu text not null,
  yukleme timestamptz not null default now()
);
alter table mahalle.gunluk enable row level security; -- politika yok: yalnız servis rolü
revoke all on mahalle.gunluk from public, anon, authenticated;
grant all on mahalle.gunluk to service_role;

create function mahalle.acilmis_gun_koru() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.gun <= ortak.bugun() and coalesce(current_setting('mahalle.duzeltme', true), '') <> 'evet'
     and (tg_op = 'DELETE' or old.kutular is distinct from new.kutular) then
    raise exception 'acilmis_gun_degisemez' using errcode = 'P0001',
      hint = 'Bilinçli düzeltme: aynı oturumda set mahalle.duzeltme = ''evet''.';
  end if;
  return coalesce(new, old);
end $$;
create trigger acilmis_gun_koru before update or delete on mahalle.gunluk for each row execute function mahalle.acilmis_gun_koru();
revoke execute on function mahalle.acilmis_gun_koru() from public;

create function public.mahalle_gunluk_oku(p_gun date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('gun', g.gun, 'kutular', g.kutular, 'icerik_surumu', g.icerik_surumu)
  from mahalle.gunluk g where g.gun = p_gun
$$;

-- İçerik yükleme: [{gun, kutular}] ve sürüm. Eksik gün eklenir; var olan yalnız gelecekte ve içerik değiştiyse güncellenir;
-- açılmış güne dokunulmaz (sayısı döner). Dönüş: { yazilan, atlanan, son_gun }.
create function public.mahalle_gunluk_yukle(p_satirlar jsonb, p_surum text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare yazilan int; toplam int := jsonb_array_length(p_satirlar);
begin
  with girdi as (
    select (x ->> 'gun')::date as gun, x -> 'kutular' as kutular from jsonb_array_elements(p_satirlar) x
  ), yaz as (
    insert into mahalle.gunluk as g (gun, kutular, icerik_surumu)
    select gun, kutular, p_surum from girdi
    on conflict (gun) do update set kutular = excluded.kutular, icerik_surumu = excluded.icerik_surumu, yukleme = now()
      where g.gun > ortak.bugun() and g.kutular is distinct from excluded.kutular
    returning 1
  ) select count(*) into yazilan from yaz;
  return jsonb_build_object('yazilan', yazilan, 'atlanan', toplam - yazilan, 'son_gun', (select max(gun) from mahalle.gunluk));
end $$;

revoke all on function public.mahalle_gunluk_oku(date), public.mahalle_gunluk_yukle(jsonb, text) from public, anon, authenticated;
grant execute on function public.mahalle_gunluk_oku(date), public.mahalle_gunluk_yukle(jsonb, text) to service_role;
