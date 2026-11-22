-- Göç 8190: Kapı Ustası oyun-ortak'a geçiyor (Vercel'den; canlıda sunucu verisi yok, taşıma gerekmez). İstekler KU-1, KU-3. Günün Üçlüsü: günde 3 görev; lig yok.
-- Kurucu kararı 22 Kasım: puan ADIL_PUAN'a geçer (0–100, sunucu süresi eşitlik bozucu), günlük ve sıralama hesapla (A17).
-- kapi.gunluk: günün içeriği cevaplarla birlikte yalnız sunucuda. Açılmış gün değişemez, silinemez;
-- bilinçli düzeltme `set kapi.duzeltme = 'evet'`. Deneme durumu ortak.denemeler'de (dogrula-kapi, oyunun deposunda).

create schema if not exists kapi;
grant usage on schema kapi to service_role;
alter default privileges in schema kapi revoke all on tables from anon, authenticated, public;
alter default privileges in schema kapi revoke execute on functions from anon, authenticated, public;
alter default privileges in schema kapi grant all on tables to service_role;

insert into ortak.oyunlar (id, ad, ayarlar) values ('kapi', 'Kapı Ustası', '{"ad":{"en_az":3,"en_cok":20,"degistirme_gun":30},"siralama":{"esitlik":"ikincil","dagilim_esigi":50},"odeme":{"revenuecat_uygulamalari":[]}}') on conflict (id) do nothing;

create table kapi.gunluk (
  gun date primary key,
  icerik jsonb not null,
  icerik_surumu text not null,
  yukleme timestamptz not null default now()
);
alter table kapi.gunluk enable row level security; -- politika yok: yalnız servis rolü
revoke all on kapi.gunluk from public, anon, authenticated;
grant all on kapi.gunluk to service_role;

create function kapi.acilmis_gun_koru() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.gun <= ortak.bugun() and coalesce(current_setting('kapi.duzeltme', true), '') <> 'evet'
     and (tg_op = 'DELETE' or old.icerik is distinct from new.icerik) then
    raise exception 'acilmis_gun_degisemez' using errcode = 'P0001',
      hint = 'Bilinçli düzeltme: aynı oturumda set kapi.duzeltme = ''evet''.';
  end if;
  return coalesce(new, old);
end $$;
create trigger acilmis_gun_koru before update or delete on kapi.gunluk for each row execute function kapi.acilmis_gun_koru();
revoke execute on function kapi.acilmis_gun_koru() from public;

create function public.kapi_gunluk_oku(p_gun date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('gun', g.gun, 'icerik', g.icerik, 'icerik_surumu', g.icerik_surumu)
  from kapi.gunluk g where g.gun = p_gun
$$;

-- İçerik yükleme: [{gun, icerik}] ve sürüm. Eksik gün eklenir; var olan yalnız gelecekte ve içerik değiştiyse güncellenir.
create function public.kapi_gunluk_yukle(p_satirlar jsonb, p_surum text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare yazilan int; toplam int := jsonb_array_length(p_satirlar);
begin
  with girdi as (
    select (x ->> 'gun')::date as gun, x -> 'icerik' as icerik from jsonb_array_elements(p_satirlar) x
  ), yaz as (
    insert into kapi.gunluk as g (gun, icerik, icerik_surumu)
    select gun, icerik, p_surum from girdi
    on conflict (gun) do update set icerik = excluded.icerik, icerik_surumu = excluded.icerik_surumu, yukleme = now()
      where g.gun > ortak.bugun() and g.icerik is distinct from excluded.icerik
    returning 1
  ) select count(*) into yazilan from yaz;
  return jsonb_build_object('yazilan', yazilan, 'atlanan', toplam - yazilan, 'son_gun', (select max(gun) from kapi.gunluk));
end $$;

revoke all on function public.kapi_gunluk_oku(date), public.kapi_gunluk_yukle(jsonb, text) from public, anon, authenticated;
grant execute on function public.kapi_gunluk_oku(date), public.kapi_gunluk_yukle(jsonb, text) to service_role;
