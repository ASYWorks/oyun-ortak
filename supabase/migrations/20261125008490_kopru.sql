-- Göç 8490: Kelime Köprüsü oyun-ortak'a geçiyor (Vercel'den; canlıda sunucu verisi yok). İstekler KK-1, KK-2.
-- Kurucu kararı 25 Kasım: puan oyunun kuralı (0–100 süresiz adım puanı; ADIL_PUAN kapsam notu), eşit puan aynı sıra
-- (esitlik ortak, süre eşitlik bozmaz); lig yok. Oyuncuya ait tablo yok (deneme ve skor ortak'ta): silme işlevi gerekmez.
-- kopru.gunluk: günün parçaları (kopru, mini, usta) ve örnek yollar yalnız sunucuda; gelecek gün istemciye dönmez (O22, O28).
-- Açılmış gün değişemez, silinemez; bilinçli düzeltme `set kopru.duzeltme = 'evet'`. Her değişiklik ortak.yonetim_kaydi'na.

create schema if not exists kopru;
grant usage on schema kopru to service_role;
alter default privileges in schema kopru revoke all on tables from anon, authenticated, public;
alter default privileges in schema kopru revoke execute on functions from anon, authenticated, public;
alter default privileges in schema kopru grant all on tables to service_role;

insert into ortak.oyunlar (id, ad, ayarlar) values ('kopru', 'Kelime Köprüsü', '{"ad":{"en_az":3,"en_cok":20,"degistirme_gun":30},"siralama":{"yon":"azalan","esitlik":"ortak","dagilim_esigi":50},"odeme":{"revenuecat_uygulamalari":[]}}') on conflict (id) do nothing;

create table kopru.gunluk (
  gun date not null,
  parca text not null check (parca in ('kopru', 'mini', 'usta')),
  birim jsonb not null,         -- mod, uçlar, tohum, bulut boyu, yasak/tür kısıtı
  par int not null check (par > 0),
  graf_surumu text not null,
  motor_surumu text not null,
  icerik_surumu text not null,
  ornek_yollar jsonb not null,  -- istemciye gitmez
  yukleme timestamptz not null default now(),
  primary key (gun, parca)
);
alter table kopru.gunluk enable row level security; -- politika yok: yalnız servis rolü
revoke all on kopru.gunluk from public, anon, authenticated;
grant all on kopru.gunluk to service_role;

create function kopru.acilmis_gun_koru() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.gun <= ortak.bugun() and coalesce(current_setting('kopru.duzeltme', true), '') <> 'evet'
     and (tg_op = 'DELETE' or (old.birim, old.par, old.graf_surumu, old.motor_surumu, old.ornek_yollar)
          is distinct from (new.birim, new.par, new.graf_surumu, new.motor_surumu, new.ornek_yollar)) then
    raise exception 'acilmis_gun_degisemez' using errcode = 'P0001',
      hint = 'Bilinçli düzeltme: aynı oturumda set kopru.duzeltme = ''evet''.';
  end if;
  return coalesce(new, old);
end $$;
create trigger acilmis_gun_koru before update or delete on kopru.gunluk for each row execute function kopru.acilmis_gun_koru();
revoke execute on function kopru.acilmis_gun_koru() from public;
create trigger yonetim_kaydi after insert or update or delete on kopru.gunluk for each row execute function ortak.yonetim_kaydet('gun');

-- Günün bütün parçaları (örnek yollar dahil; dogrula-kopru istemciye yolsuz verir).
create function public.kopru_gunluk_oku(p_gun date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('gun', g.gun, 'parca', g.parca, 'birim', g.birim, 'par', g.par,
    'graf_surumu', g.graf_surumu, 'motor_surumu', g.motor_surumu, 'icerik_surumu', g.icerik_surumu, 'ornek_yollar', g.ornek_yollar)
    order by g.parca), '[]'::jsonb)
  from kopru.gunluk g where g.gun = p_gun
$$;

-- İçerik yükleme: [{gun, parca, birim, par, graf_surumu, motor_surumu, ornek_yollar}] ve içerik sürümü. Eksik satır eklenir;
-- var olan yalnız gelecekte ve değiştiyse güncellenir. Başlangıç tarihi yükleyicide (ONIZLEME §6).
-- Dönüş: { yazilan, atlanan, son_gun, kalan_gun }.
create function public.kopru_gunluk_yukle(p_satirlar jsonb, p_surum text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare yazilan int; toplam int := jsonb_array_length(p_satirlar);
begin
  with girdi as (
    select (x ->> 'gun')::date as gun, x ->> 'parca' as parca, x -> 'birim' as birim, (x ->> 'par')::int as par,
           x ->> 'graf_surumu' as graf_surumu, x ->> 'motor_surumu' as motor_surumu, x -> 'ornek_yollar' as ornek_yollar
    from jsonb_array_elements(p_satirlar) x
  ), yaz as (
    insert into kopru.gunluk as g (gun, parca, birim, par, graf_surumu, motor_surumu, icerik_surumu, ornek_yollar)
    select gun, parca, birim, par, graf_surumu, motor_surumu, p_surum, ornek_yollar from girdi
    on conflict (gun, parca) do update set birim = excluded.birim, par = excluded.par, graf_surumu = excluded.graf_surumu,
      motor_surumu = excluded.motor_surumu, icerik_surumu = excluded.icerik_surumu, ornek_yollar = excluded.ornek_yollar, yukleme = now()
      where g.gun > ortak.bugun()
        and (g.birim, g.par, g.graf_surumu, g.motor_surumu, g.ornek_yollar)
            is distinct from (excluded.birim, excluded.par, excluded.graf_surumu, excluded.motor_surumu, excluded.ornek_yollar)
    returning 1
  ) select count(*) into yazilan from yaz;
  return jsonb_build_object('yazilan', yazilan, 'atlanan', toplam - yazilan,
    'son_gun', (select max(gun) from kopru.gunluk), 'kalan_gun', (select max(gun) - ortak.bugun() from kopru.gunluk));
end $$;

revoke all on function public.kopru_gunluk_oku(date), public.kopru_gunluk_yukle(jsonb, text) from public, anon, authenticated;
grant execute on function public.kopru_gunluk_oku(date), public.kopru_gunluk_yukle(jsonb, text) to service_role;
