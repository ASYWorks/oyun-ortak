-- Göç 8500: Kulis (sandik-ustasi, yeni oyun; ad kesinleşmedi, satır adı çalışma adıdır). İstekler KU-1, KU-2.
-- Sıralama puan, azalan, eşitlik ikincil (sunucu süresi; ADIL_PUAN). Haftalık lig: en iyi 5 gün, 5 kademe, eşitler aynı sıra.
-- Yayın önizlemede (ONIZLEME §5). Oyuncuya ait tablo yok (deneme ve skor ortak'ta): silme işlevi gerekmez.
-- kulis.gunluk: Günün Sandığı (tur 'gunluk') ve Haftanın Kurulu (tur 'hafta', gun = haftanın pazartesisi). Seviye verisi
-- cevapsızdır; cevap (usta, ipucuYolu) yalnız sunucuda, dogrula-kulis istemciye vermez (O22, O28).
-- Açılmış gün değişemez, silinemez; bilinçli düzeltme `set kulis.duzeltme = 'evet'`. Her değişiklik ortak.yonetim_kaydi'na.

create schema if not exists kulis;
grant usage on schema kulis to service_role;
alter default privileges in schema kulis revoke all on tables from anon, authenticated, public;
alter default privileges in schema kulis revoke execute on functions from anon, authenticated, public;
alter default privileges in schema kulis grant all on tables to service_role;

insert into ortak.oyunlar (id, ad, ayarlar) values ('kulis', 'Kulis', '{"ad":{"en_az":3,"en_cok":20,"degistirme_gun":30},"yayin":"onizleme","siralama":{"yon":"azalan","esitlik":"ikincil","dagilim_esigi":50},"lig":{"kademeler":["Gönüllü","Sayım Görevlisi","Kampanya Sorumlusu","Kurul Üyesi","Kulis Ustası"],"grup_boyu":30,"cikis_orani":0.2,"inis_orani":0.2,"en_iyi_gun":5,"esitlik":"ortak","bant_genisligi":0},"odeme":{"revenuecat_uygulamalari":[]}}') on conflict (id) do nothing;

create table kulis.gunluk (
  gun date not null,
  tur text not null check (tur in ('gunluk', 'hafta')),
  seviye jsonb not null,        -- cevapsız seviye verisi
  cevap jsonb not null,         -- usta, ipucuYolu; istemciye gitmez
  kural_surumu text not null,   -- rulesVersion
  icerik_ozeti text not null,   -- contentHash
  icerik_surumu text not null,
  yukleme timestamptz not null default now(),
  primary key (gun, tur),
  check (tur = 'gunluk' or extract(isodow from gun) = 1)
);
alter table kulis.gunluk enable row level security; -- politika yok: yalnız servis rolü
revoke all on kulis.gunluk from public, anon, authenticated;
grant all on kulis.gunluk to service_role;

create function kulis.acilmis_gun_koru() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.gun <= ortak.bugun() and coalesce(current_setting('kulis.duzeltme', true), '') <> 'evet'
     and (tg_op = 'DELETE' or (old.seviye, old.cevap, old.kural_surumu, old.icerik_ozeti)
          is distinct from (new.seviye, new.cevap, new.kural_surumu, new.icerik_ozeti)) then
    raise exception 'acilmis_gun_degisemez' using errcode = 'P0001',
      hint = 'Bilinçli düzeltme: aynı oturumda set kulis.duzeltme = ''evet''.';
  end if;
  return coalesce(new, old);
end $$;
create trigger acilmis_gun_koru before update or delete on kulis.gunluk for each row execute function kulis.acilmis_gun_koru();
revoke execute on function kulis.acilmis_gun_koru() from public;
create trigger yonetim_kaydi after insert or update or delete on kulis.gunluk for each row execute function ortak.yonetim_kaydet('gun');

-- Bir gün ya da hafta (cevap dahil; dogrula-kulis istemciye cevapsız verir). Yoksa null.
create function public.kulis_gunluk_oku(p_gun date, p_tur text default 'gunluk') returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('gun', g.gun, 'tur', g.tur, 'seviye', g.seviye, 'cevap', g.cevap,
    'kural_surumu', g.kural_surumu, 'icerik_ozeti', g.icerik_ozeti, 'icerik_surumu', g.icerik_surumu)
  from kulis.gunluk g where g.gun = p_gun and g.tur = p_tur
$$;

-- İçerik yükleme: [{gun, tur, seviye, cevap, kural_surumu, icerik_ozeti}] ve içerik sürümü. Eksik satır eklenir; var olan yalnız
-- gelecekte ve değiştiyse güncellenir. Dönüş: { yazilan, atlanan, son_gun, kalan_gun } (günlük tür; en az 14 gün ileri, KU-2).
create function public.kulis_gunluk_yukle(p_satirlar jsonb, p_surum text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare yazilan int; toplam int := jsonb_array_length(p_satirlar);
begin
  with girdi as (
    select (x ->> 'gun')::date as gun, coalesce(x ->> 'tur', 'gunluk') as tur, x -> 'seviye' as seviye, x -> 'cevap' as cevap,
           x ->> 'kural_surumu' as kural_surumu, x ->> 'icerik_ozeti' as icerik_ozeti
    from jsonb_array_elements(p_satirlar) x
  ), yaz as (
    insert into kulis.gunluk as g (gun, tur, seviye, cevap, kural_surumu, icerik_ozeti, icerik_surumu)
    select gun, tur, seviye, cevap, kural_surumu, icerik_ozeti, p_surum from girdi
    on conflict (gun, tur) do update set seviye = excluded.seviye, cevap = excluded.cevap, kural_surumu = excluded.kural_surumu,
      icerik_ozeti = excluded.icerik_ozeti, icerik_surumu = excluded.icerik_surumu, yukleme = now()
      where g.gun > ortak.bugun()
        and (g.seviye, g.cevap, g.kural_surumu, g.icerik_ozeti)
            is distinct from (excluded.seviye, excluded.cevap, excluded.kural_surumu, excluded.icerik_ozeti)
    returning 1
  ) select count(*) into yazilan from yaz;
  return jsonb_build_object('yazilan', yazilan, 'atlanan', toplam - yazilan,
    'son_gun', (select max(gun) from kulis.gunluk where tur = 'gunluk'),
    'kalan_gun', (select max(gun) - ortak.bugun() from kulis.gunluk where tur = 'gunluk'));
end $$;

revoke all on function public.kulis_gunluk_oku(date, text), public.kulis_gunluk_yukle(jsonb, text) from public, anon, authenticated;
grant execute on function public.kulis_gunluk_oku(date, text), public.kulis_gunluk_yukle(jsonb, text) to service_role;
