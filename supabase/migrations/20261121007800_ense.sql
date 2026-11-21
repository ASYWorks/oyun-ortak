-- Göç 7800: Ense Nasıl Olsun oyun-ortak'a geçiyor (Upstash/Vercel bırakılıyor; canlıda veri yok, taşıma gerekmez).
-- Sözleşme: ense-nasil-olsun/docs/DOGRULA_SOZLESME.md (dogrula-ense, oyunun deposunda). Kararlar ISTEKLER.md EN-1..EN-5.
-- - ortak.oyunlar 'ense': ad kuralı ortak (3–20), günlük sıralama; büyük puan önde, eşitlikte ikincil küçük önde
--   (dogrula-ense ikincil'i motorToplam ve süreden tek sayıya kodlar). Lig yok. Oyuna özgü kullanıcı tablosu olmadığı için
--   silme_fonksiyonu yok: ortak silme yolu (skorlar, denemeler, kayıt, oyuncu) yeter.
-- - ense.gunluk: günün görevi, cevaplarla birlikte yalnız sunucuda (EN-2). İstemci açık görünümü dogrula-ense'den alır.
--   Yalnız servis rolü okur/yazar. Açılmış gün (bugün ve öncesi) değişemez, silinemez; bilinçli düzeltme
--   `set ense.duzeltme = 'evet'` ile (Halka'daki gibi).

create schema if not exists ense;
grant usage on schema ense to service_role;
alter default privileges in schema ense revoke all on tables from anon, authenticated, public;
alter default privileges in schema ense revoke execute on functions from anon, authenticated, public;
alter default privileges in schema ense grant all on tables to service_role;

insert into ortak.oyunlar (id, ad, ayarlar) values (
  'ense', 'Ense Nasıl Olsun', '{
    "ad": { "en_az": 3, "en_cok": 20, "degistirme_gun": 30 },
    "siralama": { "esitlik": "ikincil", "dagilim_esigi": 50 },
    "odeme": { "revenuecat_uygulamalari": [] }
  }'
) on conflict (id) do nothing;

create table ense.gunluk (
  gun date primary key,
  resmi jsonb not null,          -- günün resmî görevi, cevaplar dahil (istemciye gitmez)
  prova jsonb not null,          -- sıralamasız prova görevi (istemciye tam gider)
  icerik_surumu text not null,   -- content/daily-pool.json sürümü
  yukleme timestamptz not null default now()
);
alter table ense.gunluk enable row level security; -- politika yok: yalnız servis rolü
revoke all on ense.gunluk from public, anon, authenticated;
grant all on ense.gunluk to service_role;

create function ense.acilmis_gun_koru() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.gun <= ortak.bugun() and coalesce(current_setting('ense.duzeltme', true), '') <> 'evet'
     and (tg_op = 'DELETE' or (old.resmi, old.prova) is distinct from (new.resmi, new.prova)) then
    raise exception 'acilmis_gun_degisemez' using errcode = 'P0001',
      hint = 'Bilinçli düzeltme: aynı oturumda set ense.duzeltme = ''evet''.';
  end if;
  return coalesce(new, old);
end $$;
create trigger acilmis_gun_koru before update or delete on ense.gunluk for each row execute function ense.acilmis_gun_koru();

-- ense şeması API'ye açılmaz (Halka kalıbı): dogrula-ense ve yükleme betiği servis anahtarıyla public sarmalayıcıları çağırır.
-- Bir günün görevi (resmi + prova); yoksa null.
create function public.ense_gunluk_oku(p_gun date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('gun', g.gun, 'resmi', g.resmi, 'prova', g.prova, 'icerik_surumu', g.icerik_surumu)
  from ense.gunluk g where g.gun = p_gun
$$;

-- İçerik yükleme: [{gun, resmi, prova}] ve sürüm. Gelecek günler eklenir ya da güncellenir; açılmış günlere dokunulmaz
-- (sessizce atlanır, sayısı döner). Dönüş: { yazilan, atlanan, son_gun }.
create function public.ense_gunluk_yukle(p_satirlar jsonb, p_surum text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare yazilan int; toplam int := jsonb_array_length(p_satirlar);
begin
  with girdi as (
    select (x ->> 'gun')::date as gun, x -> 'resmi' as resmi, x -> 'prova' as prova
    from jsonb_array_elements(p_satirlar) x
  ), yaz as (
    insert into ense.gunluk as g (gun, resmi, prova, icerik_surumu)
    select gun, resmi, prova, p_surum from girdi where gun > ortak.bugun()
    on conflict (gun) do update set resmi = excluded.resmi, prova = excluded.prova, icerik_surumu = excluded.icerik_surumu, yukleme = now()
    returning 1
  ) select count(*) into yazilan from yaz;
  return jsonb_build_object('yazilan', yazilan, 'atlanan', toplam - yazilan, 'son_gun', (select max(gun) from ense.gunluk));
end $$;

revoke all on function public.ense_gunluk_oku(date), public.ense_gunluk_yukle(jsonb, text) from public, anon, authenticated;
grant execute on function public.ense_gunluk_oku(date), public.ense_gunluk_yukle(jsonb, text) to service_role;
