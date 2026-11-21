-- Göç 8000: Remzle (eski Şifre Bürosu) oyun-ortak'a geçiyor (Neon/Vercel bırakılıyor; canlıda gerçek veri yok).
-- Sözleşme: sifre-burosu/docs/DOGRULA_SOZLESME.md (dogrula-remzle, oyunun deposunda). Kararlar ISTEKLER.md RZ-1..RZ-5.
-- - ortak.oyunlar 'remzle': ortak ad kuralı, günlük sıralama, büyük puan önde, eşitlikte ikincil küçük önde; lig yok;
--   oyuna özgü kullanıcı tablosu yok (bölüm ilerlemesi bulut kaydında), silme ortak yoldan.
-- - remzle.gunluk_anahtar: günün üç katmanının cevap özeti (SHA-256, pepper Edge gizlisi REMZLE_PEPPER) ve ipuçları.
--   Yalnız servis rolü. Açılmış gün (bugün ve öncesi) değişemez, silinemez (`set remzle.duzeltme = 'evet'` ile bilinçli
--   düzeltme); her değişiklik yönetim kaydına düşer.
-- - Şema API'ye açılmaz: dogrula-remzle ve yükleme betiği servis anahtarıyla public.remzle_anahtar_oku / _yukle'yi çağırır.

create schema if not exists remzle;
grant usage on schema remzle to service_role;
alter default privileges in schema remzle revoke all on tables from anon, authenticated, public;
alter default privileges in schema remzle revoke execute on functions from anon, authenticated, public;
alter default privileges in schema remzle grant all on tables to service_role;

insert into ortak.oyunlar (id, ad, ayarlar) values (
  'remzle', 'Remzle', '{
    "ad": { "en_az": 3, "en_cok": 20, "degistirme_gun": 30 },
    "siralama": { "esitlik": "ikincil", "dagilim_esigi": 50 },
    "odeme": { "revenuecat_uygulamalari": [] }
  }'
) on conflict (id) do nothing;

create table remzle.gunluk_anahtar (
  gun date not null,
  katman smallint not null check (katman between 1 and 3),
  cevap_ozet text not null check (cevap_ozet ~ '^[0-9a-f]{64}$'),
  ipuclari jsonb not null check (jsonb_typeof(ipuclari) = 'array' and jsonb_array_length(ipuclari) = 3),
  zorluk smallint not null,
  icerik_surumu text not null,
  yukleme timestamptz not null default now(),
  primary key (gun, katman)
);
alter table remzle.gunluk_anahtar enable row level security; -- politika yok: yalnız servis rolü
revoke all on remzle.gunluk_anahtar from public, anon, authenticated;
grant all on remzle.gunluk_anahtar to service_role;

create function remzle.acilmis_gun_koru() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.gun <= ortak.bugun() and coalesce(current_setting('remzle.duzeltme', true), '') <> 'evet'
     and (tg_op = 'DELETE' or (old.cevap_ozet, old.ipuclari, old.zorluk) is distinct from (new.cevap_ozet, new.ipuclari, new.zorluk)) then
    raise exception 'acilmis_gun_degisemez' using errcode = 'P0001',
      hint = 'Bilinçli düzeltme: aynı oturumda set remzle.duzeltme = ''evet''; değişiklik yönetim kaydına düşer.';
  end if;
  return coalesce(new, old);
end $$;
create trigger acilmis_gun_koru before update or delete on remzle.gunluk_anahtar for each row execute function remzle.acilmis_gun_koru();
create trigger yonetim_kaydi after insert or update or delete on remzle.gunluk_anahtar for each row execute function ortak.yonetim_kaydet('gun');

-- Bir günün üç katmanı (katman sırasıyla); gün yoksa boş dizi.
create function public.remzle_anahtar_oku(p_gun date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('katman', a.katman, 'cevap_ozet', a.cevap_ozet, 'ipuclari', a.ipuclari,
                                               'zorluk', a.zorluk, 'icerik_surumu', a.icerik_surumu) order by a.katman), '[]'::jsonb)
  from remzle.gunluk_anahtar a where a.gun = p_gun
$$;

-- İçerik yükleme: [{gun, katman, cevap_ozet, ipuclari, zorluk}] ve sürüm. Eksik satır (her gün) eklenir; var olan satır
-- yalnız gelecek günde ve sürüm farklıysa güncellenir; açılmış güne dokunulmaz. Dönüş: { yazilan, atlanan, son_gun }.
create function public.remzle_anahtar_yukle(p_satirlar jsonb, p_surum text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare yazilan int; toplam int := jsonb_array_length(p_satirlar);
begin
  with girdi as (
    select (x ->> 'gun')::date as gun, (x ->> 'katman')::smallint as katman, x ->> 'cevap_ozet' as cevap_ozet,
           x -> 'ipuclari' as ipuclari, (x ->> 'zorluk')::smallint as zorluk
    from jsonb_array_elements(p_satirlar) x
  ), yaz as (
    insert into remzle.gunluk_anahtar as a (gun, katman, cevap_ozet, ipuclari, zorluk, icerik_surumu)
    select gun, katman, cevap_ozet, ipuclari, zorluk, p_surum from girdi
    on conflict (gun, katman) do update set cevap_ozet = excluded.cevap_ozet, ipuclari = excluded.ipuclari,
      zorluk = excluded.zorluk, icerik_surumu = excluded.icerik_surumu, yukleme = now()
      where a.gun > ortak.bugun() and a.icerik_surumu is distinct from excluded.icerik_surumu
    returning 1
  ) select count(*) into yazilan from yaz;
  return jsonb_build_object('yazilan', yazilan, 'atlanan', toplam - yazilan, 'son_gun', (select max(gun) from remzle.gunluk_anahtar));
end $$;

revoke all on function public.remzle_anahtar_oku(date), public.remzle_anahtar_yukle(jsonb, text) from public, anon, authenticated;
grant execute on function public.remzle_anahtar_oku(date), public.remzle_anahtar_yukle(jsonb, text) to service_role;
