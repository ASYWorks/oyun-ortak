-- Göç 8200: Koz Hesabı oyun-ortak'a geçiyor (Vercel'den; canlıda sunucu verisi yok, taşıma gerekmez). İstekler KH-12, KH-13 (temel). Günde 3 el; lig (20 kişi, en iyi 5 gün) kademe adlarıyla ayrı göçle; düello ve arkadaşlık (KH-15) ayrı göçle.
-- Kurucu kararı 22 Kasım: puan ADIL_PUAN'a geçer (0–100, sunucu süresi eşitlik bozucu), günlük ve sıralama hesapla (A17).
-- koz.gunluk: günün içeriği cevaplarla birlikte yalnız sunucuda. Açılmış gün değişemez, silinemez;
-- bilinçli düzeltme `set koz.duzeltme = 'evet'`. Deneme durumu ortak.denemeler'de (dogrula-koz, oyunun deposunda).

create schema if not exists koz;
grant usage on schema koz to service_role;
alter default privileges in schema koz revoke all on tables from anon, authenticated, public;
alter default privileges in schema koz revoke execute on functions from anon, authenticated, public;
alter default privileges in schema koz grant all on tables to service_role;

insert into ortak.oyunlar (id, ad, ayarlar) values ('koz', 'Koz Hesabı', '{"ad":{"en_az":3,"en_cok":20,"degistirme_gun":30,"yasakli":["koz","hesabi","bahis","kumar"]},"siralama":{"esitlik":"ikincil","dagilim_esigi":50},"odeme":{"revenuecat_uygulamalari":[]}}') on conflict (id) do nothing;

create table koz.gunluk (
  gun date primary key,
  eller jsonb not null,
  icerik_surumu text not null,
  yukleme timestamptz not null default now()
);
alter table koz.gunluk enable row level security; -- politika yok: yalnız servis rolü
revoke all on koz.gunluk from public, anon, authenticated;
grant all on koz.gunluk to service_role;

create function koz.acilmis_gun_koru() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.gun <= ortak.bugun() and coalesce(current_setting('koz.duzeltme', true), '') <> 'evet'
     and (tg_op = 'DELETE' or old.eller is distinct from new.eller) then
    raise exception 'acilmis_gun_degisemez' using errcode = 'P0001',
      hint = 'Bilinçli düzeltme: aynı oturumda set koz.duzeltme = ''evet''.';
  end if;
  return coalesce(new, old);
end $$;
create trigger acilmis_gun_koru before update or delete on koz.gunluk for each row execute function koz.acilmis_gun_koru();
revoke execute on function koz.acilmis_gun_koru() from public;

create function public.koz_gunluk_oku(p_gun date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('gun', g.gun, 'eller', g.eller, 'icerik_surumu', g.icerik_surumu)
  from koz.gunluk g where g.gun = p_gun
$$;

-- İçerik yükleme: [{gun, eller}] ve sürüm. Eksik gün eklenir; var olan yalnız gelecekte ve içerik değiştiyse güncellenir.
create function public.koz_gunluk_yukle(p_satirlar jsonb, p_surum text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare yazilan int; toplam int := jsonb_array_length(p_satirlar);
begin
  with girdi as (
    select (x ->> 'gun')::date as gun, x -> 'eller' as icerik from jsonb_array_elements(p_satirlar) x
  ), yaz as (
    insert into koz.gunluk as g (gun, eller, icerik_surumu)
    select gun, icerik, p_surum from girdi
    on conflict (gun) do update set eller = excluded.eller, icerik_surumu = excluded.icerik_surumu, yukleme = now()
      where g.gun > ortak.bugun() and g.eller is distinct from excluded.eller
    returning 1
  ) select count(*) into yazilan from yaz;
  return jsonb_build_object('yazilan', yazilan, 'atlanan', toplam - yazilan, 'son_gun', (select max(gun) from koz.gunluk));
end $$;

revoke all on function public.koz_gunluk_oku(date), public.koz_gunluk_yukle(jsonb, text) from public, anon, authenticated;
grant execute on function public.koz_gunluk_oku(date), public.koz_gunluk_yukle(jsonb, text) to service_role;
