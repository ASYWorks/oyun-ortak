-- Göç 8470: El Bitir oyun-ortak'a geçiyor (Vercel'den; canlıda sunucu verisi yok). İstekler EB-1, EB-2.
-- Kurucu kararı (el-bitir KARARLAR 73-75): sıralama puan (ADIL_PUAN, sunucu süresi eşitlik bozucu), yalnız Günün Eli ana eli sıralamalı, lig yok.
-- elbitir.gunluk: günün ana eli ve cevabı yalnız sunucuda; dogrula-elbitir istemciye cevapsız verir (O22, O28).
-- Açılmış gün değişemez, silinemez; bilinçli düzeltme `set elbitir.duzeltme = 'evet'`. Her değişiklik ortak.yonetim_kaydi'na.
-- Oyuncuya ait tablo yok (deneme ve skor ortak'ta): hesap silme işlevi gerekmez.

create schema if not exists elbitir;
grant usage on schema elbitir to service_role;
alter default privileges in schema elbitir revoke all on tables from anon, authenticated, public;
alter default privileges in schema elbitir revoke execute on functions from anon, authenticated, public;
alter default privileges in schema elbitir grant all on tables to service_role;

insert into ortak.oyunlar (id, ad, ayarlar) values ('elbitir', 'El Bitir', '{"ad":{"en_az":3,"en_cok":20,"degistirme_gun":30},"siralama":{"esitlik":"ikincil","dagilim_esigi":50},"odeme":{"revenuecat_uygulamalari":[]}}') on conflict (id) do nothing;

create table elbitir.gunluk (
  gun date primary key,
  icerik jsonb not null,  -- gösterge, el, deste, yan
  par int not null check (par > 0),
  cevap jsonb not null,   -- istemciye gitmez
  icerik_surumu text not null,
  yukleme timestamptz not null default now()
);
alter table elbitir.gunluk enable row level security; -- politika yok: yalnız servis rolü
revoke all on elbitir.gunluk from public, anon, authenticated;
grant all on elbitir.gunluk to service_role;

create function elbitir.acilmis_gun_koru() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.gun <= ortak.bugun() and coalesce(current_setting('elbitir.duzeltme', true), '') <> 'evet'
     and (tg_op = 'DELETE' or (old.icerik, old.par, old.cevap) is distinct from (new.icerik, new.par, new.cevap)) then
    raise exception 'acilmis_gun_degisemez' using errcode = 'P0001',
      hint = 'Bilinçli düzeltme: aynı oturumda set elbitir.duzeltme = ''evet''.';
  end if;
  return coalesce(new, old);
end $$;
create trigger acilmis_gun_koru before update or delete on elbitir.gunluk for each row execute function elbitir.acilmis_gun_koru();
revoke execute on function elbitir.acilmis_gun_koru() from public;
create trigger yonetim_kaydi after insert or update or delete on elbitir.gunluk for each row execute function ortak.yonetim_kaydet('gun');

create function public.elbitir_gunluk_oku(p_gun date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('gun', g.gun, 'icerik', g.icerik, 'par', g.par, 'cevap', g.cevap, 'icerik_surumu', g.icerik_surumu)
  from elbitir.gunluk g where g.gun = p_gun
$$;

-- İçerik yükleme: [{gun, icerik, par, cevap}] ve sürüm. Eksik gün eklenir; var olan yalnız gelecekte ve değiştiyse güncellenir.
-- Başlangıç tarihi yükleyicide verilir (ONIZLEME §6). Dönüş: { yazilan, atlanan, son_gun, kalan_gun }.
create function public.elbitir_gunluk_yukle(p_satirlar jsonb, p_surum text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare yazilan int; toplam int := jsonb_array_length(p_satirlar);
begin
  with girdi as (
    select (x ->> 'gun')::date as gun, x -> 'icerik' as icerik, (x ->> 'par')::int as par, x -> 'cevap' as cevap
    from jsonb_array_elements(p_satirlar) x
  ), yaz as (
    insert into elbitir.gunluk as g (gun, icerik, par, cevap, icerik_surumu)
    select gun, icerik, par, cevap, p_surum from girdi
    on conflict (gun) do update set icerik = excluded.icerik, par = excluded.par, cevap = excluded.cevap,
      icerik_surumu = excluded.icerik_surumu, yukleme = now()
      where g.gun > ortak.bugun() and (g.icerik, g.par, g.cevap) is distinct from (excluded.icerik, excluded.par, excluded.cevap)
    returning 1
  ) select count(*) into yazilan from yaz;
  return jsonb_build_object('yazilan', yazilan, 'atlanan', toplam - yazilan,
    'son_gun', (select max(gun) from elbitir.gunluk), 'kalan_gun', (select max(gun) - ortak.bugun() from elbitir.gunluk));
end $$;

revoke all on function public.elbitir_gunluk_oku(date), public.elbitir_gunluk_yukle(jsonb, text) from public, anon, authenticated;
grant execute on function public.elbitir_gunluk_oku(date), public.elbitir_gunluk_yukle(jsonb, text) to service_role;
