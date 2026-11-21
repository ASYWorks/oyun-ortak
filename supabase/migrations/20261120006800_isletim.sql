-- İşletim incelemesi (20 Kasım; kurucu: canlı işletim, veri güvenilirliği ve bakım). Belge: docs/ISLETIM.md.
-- 1) Haftalık ödül işleri gece yarısı yığılmasından çıkarıldı (Pazartesi 00:15 ve 00:01 İstanbul → 03:15 ve 03:05).
--    İkisi de haftayı tarihten hesaplar ve "on conflict do nothing" ile yazar: saat kayması sonucu değiştirmez, iki kez
--    çalışması çift ödül üretmez. Halka turnuva ödülü 14 gün geriye bakar: kaçırılan çalışma bir sonrakinde telafi edilir.
-- 2) ortak.isletim_durumu(): işlerin son başarısı/gecikmesi/hatası, içerik kalan gün, kapanmamış lig, ödülsüz turnuva,
--    son 24 saat sayıları. Yalnız servis rolü (scripts/saglik.ts).
-- 3) ortak.yonetim_kaydi: bulmaca, oyun ayarı, ürün ve hak değişikliklerinde kim (rol, uygulama), ne (tablo, anahtar,
--    değişen sütunlar, eski/yeni özet), ne zaman. Yalnız gerçekten değişen satır yazılır.
-- 4) Açılmış günün bulmacası sessizce değiştirilemez (halka.gecmis_bulmaca_koru): cevap, halka, çözüm, kural ya da başlangıç
--    değişirse işlem reddedilir; bilinçli düzeltme oturumda `set halka.duzeltme = 'evet'` ile yapılır ve yönetim kaydına düşer.
-- 5) acilis yanıtında oyunun sunucu kontrollü bayrakları (ortak.oyunlar.ayarlar.bayraklar).

select cron.schedule('halka-turnuva-odul', '15 0 * * 1', $$select halka.turnuva_odul_ver()$$);    -- Pazartesi 03:15 İstanbul
select cron.schedule('sticky-haftalik-odul', '5 0 * * 1', $$select sticky.haftalik_odul()$$);     -- Pazartesi 03:05 İstanbul

-- ---------------------------------------------------------------- yönetim kaydı
create table ortak.yonetim_kaydi (
  id bigserial primary key,
  zaman timestamptz not null default now(),
  tablo text not null,
  islem text not null,
  anahtar text,
  rol text not null,
  uygulama text,
  degisen text[],
  eski_ozet text,
  yeni_ozet text
);
alter table ortak.yonetim_kaydi enable row level security;
revoke all on ortak.yonetim_kaydi from anon, authenticated;
create index yonetim_kaydi_zaman on ortak.yonetim_kaydi (zaman);

create function ortak.yonetim_kaydet() returns trigger
language plpgsql security definer set search_path = '' as $$
declare e jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
        y jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
        d text[];
begin
  if tg_op = 'UPDATE' then
    select array_agg(k order by k) into d from jsonb_object_keys(y) k where (e -> k) is distinct from (y -> k);
    if d is null then return new; end if; -- aynı içerik yeniden yazıldı: kayıt yok
  end if;
  insert into ortak.yonetim_kaydi (tablo, islem, anahtar, rol, uygulama, degisen, eski_ozet, yeni_ozet)
  values (tg_table_schema || '.' || tg_table_name, tg_op, coalesce(y, e) ->> tg_argv[0],
          coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), current_user),
          nullif(current_setting('application_name', true), ''), d,
          left(md5(e::text), 16), left(md5(y::text), 16));
  return coalesce(new, old);
end $$;
revoke execute on function ortak.yonetim_kaydet() from public, anon, authenticated;

create trigger yonetim_kaydi after insert or update or delete on halka.gunluk_bulmacalar for each row execute function ortak.yonetim_kaydet('tarih');
create trigger yonetim_kaydi after insert or update or delete on halka.turnuva_bulmacalar for each row execute function ortak.yonetim_kaydet('kimlik');
create trigger yonetim_kaydi after insert or update or delete on ortak.oyunlar for each row execute function ortak.yonetim_kaydet('id');
create trigger yonetim_kaydi after insert or update or delete on ortak.urunler for each row execute function ortak.yonetim_kaydet('urun');
create trigger yonetim_kaydi after insert or update or delete on ortak.haklar for each row execute function ortak.yonetim_kaydet('kullanici_id');

-- ---------------------------------------------------------------- açılmış bulmaca koruması
create function halka.gecmis_bulmaca_koru() returns trigger
language plpgsql set search_path = '' as $$
declare acik boolean := (to_jsonb(old) ->> case tg_table_name when 'gunluk_bulmacalar' then 'tarih' else 'basla' end)::date
                         <= ortak.bugun();
begin
  if acik and coalesce(current_setting('halka.duzeltme', true), '') <> 'evet'
     and (tg_op = 'DELETE'
          or (to_jsonb(old) -> 'halkalar', to_jsonb(old) -> 'cevaplar', to_jsonb(old) -> 'cozum', to_jsonb(old) -> 'kurallar', to_jsonb(old) -> 'baslangic')
             is distinct from
             (to_jsonb(new) -> 'halkalar', to_jsonb(new) -> 'cevaplar', to_jsonb(new) -> 'cozum', to_jsonb(new) -> 'kurallar', to_jsonb(new) -> 'baslangic')) then
    raise exception 'acilmis_bulmaca_degisemez' using errcode = 'P0001',
      hint = 'Bilinçli düzeltme: aynı oturumda set halka.duzeltme = ''evet''; değişiklik yönetim kaydına düşer (docs/ISLETIM.md §9).';
  end if;
  return coalesce(new, old);
end $$;
create trigger gecmis_bulmaca_koru before update or delete on halka.gunluk_bulmacalar for each row execute function halka.gecmis_bulmaca_koru();
create trigger gecmis_bulmaca_koru before update or delete on halka.turnuva_bulmacalar for each row execute function halka.gecmis_bulmaca_koru();

-- ---------------------------------------------------------------- işletim durumu
create function ortak.isletim_durumu() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'zaman', now(),
    'bugun', ortak.bugun(),
    'isler', (
      select jsonb_agg(jsonb_build_object(
        'ad', j.jobname, 'zamanlama', j.schedule, 'etkin', j.active,
        'son_basari', s.son, 'son_sure_ms', s.sure, 'basarisiz_24s', s.hata, 'son_hata', s.mesaj,
        -- Beklenen en geç başarı: dakikalık 10 dk, */N dakikalık 40 dk, saatlik 2 sa, günlük 26 sa, haftalık 8 gün.
        'gecikti', s.son is null or s.son < now() - case
          when j.schedule like '* %' then interval '10 minutes'
          when j.schedule like '*/%' then interval '40 minutes'
          when j.schedule ~ '^\d+ \* ' then interval '2 hours'
          when j.schedule ~ '^\d+ \d+ \* \* \*$' then interval '26 hours'
          else interval '8 days' end) order by j.jobname)
      from cron.job j,
      lateral (select max(r.end_time) filter (where r.status = 'succeeded') as son,
                      (select (extract(epoch from r2.end_time - r2.start_time) * 1000)::int from cron.job_run_details r2
                        where r2.jobid = j.jobid and r2.status = 'succeeded' order by r2.end_time desc limit 1) as sure,
                      count(*) filter (where r.status = 'failed' and r.start_time > now() - interval '24 hours') as hata,
                      (select left(r3.return_message, 200) from cron.job_run_details r3
                        where r3.jobid = j.jobid and r3.status = 'failed' order by r3.start_time desc limit 1) as mesaj
               from cron.job_run_details r where r.jobid = j.jobid) s),
    'icerik', jsonb_build_object(
      'halka_gunluk_son', (select max(tarih) from halka.gunluk_bulmacalar),
      'halka_gunluk_kalan_gun', (select max(tarih) - ortak.bugun() from halka.gunluk_bulmacalar),
      'halka_bugun_var', exists (select 1 from halka.gunluk_bulmacalar where tarih = ortak.bugun()),
      'halka_turnuva_son_bitis', (select max(bitir) from halka.turnuva_bulmacalar),
      'sezgi_gunluk_son', (select max(day) from sezgi.daily_puzzles)),
    'bekleyen', jsonb_build_object(
      'kapanmamis_gecmis_lig_grubu', (select count(*) from ortak.lig_gruplari
                                      where not kapandi and hafta < ortak.iso_hafta(ortak.bugun())),
      'odulsuz_turnuva', (select count(*) from halka.turnuva_bulmacalar t
                          where halka.cevap_acik(t.bitir, now() - interval '6 hours') and t.bitir >= ortak.bugun() - 14
                            and exists (select 1 from ortak.skorlar s where s.oyun_id = 'halka' and s.tur = 'etkinlik' and s.donem = t.kimlik)
                            and not exists (select 1 from ortak.oduller o where o.oyun_id = 'halka'
                                            and o.kaynak = 'etkinlik:' || t.kimlik and o.odul like 'sira:%'))),
    'son_24s', jsonb_build_object(
      'skor', (select count(*) from ortak.skorlar where olusturma > now() - interval '24 hours'),
      'yeni_kullanici', (select count(*) from auth.users where created_at > now() - interval '24 hours'),
      'odeme_olayi', (select count(*) from ortak.odeme_olaylari where alindi > now() - interval '24 hours'),
      'yonetim_degisikligi', (select count(*) from ortak.yonetim_kaydi where zaman > now() - interval '24 hours')),
    'boyut', jsonb_build_object(
      'veritabani_mb', round(pg_database_size(current_database()) / 1048576.0, 1),
      'hiz_sinirlari_satir', (select count(*) from ortak.hiz_sinirlari)))
$$;
revoke execute on function ortak.isletim_durumu() from public, anon, authenticated;
grant execute on function ortak.isletim_durumu() to service_role;

create or replace function ortak.acilis(p_oyun text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := ortak.kim();
  b jsonb;
  o ortak.oyuncular;
  od text;
begin
  b := ortak.ben(p_oyun);
  select * into o from ortak.oyuncular where oyun_id = p_oyun and kullanici_id = u;
  select md5(coalesce(string_agg(odul || '|' || kazanildi::text, ',' order by odul), '')) into od
    from ortak.oduller where oyun_id = p_oyun and kullanici_id = u;
  return jsonb_build_object(
    'ben', b,
    'surum', jsonb_build_object(
      -- Bugünün tarihi de girer: şimdiki seri gün değişince değişir (profil günde en çok bir kez yenilenir).
      'profil', md5(concat_ws('|', ortak.bugun(), o.ad, o.kademe, o.profil_gizli, o.desen, od,
                 (select count(*) || ':' || coalesce(max(s.olusturma)::text, '') from ortak.skorlar s
                  where s.oyun_id = p_oyun and s.kullanici_id = u))),
      'oduller', od,
      'haklar', (select md5(coalesce(string_agg(h.hak || '|' || h.durum || '|' || h.guncelleme::text, ',' order by h.hak), ''))
                 from ortak.haklar h where h.oyun_id = p_oyun and h.kullanici_id = u),
      'kayit', coalesce((select k.surum from ortak.kayitlar k where k.oyun_id = p_oyun and k.kullanici_id = u), 0)))
    -- Lig durumu açılışta zaten isteniyordu ve sık değişir (grup üyelerinin skoru): damga yerine kendisi döner (oyunda lig varsa).
    || case when exists (select 1 from ortak.oyunlar where id = p_oyun and ayarlar ? 'lig')
            then jsonb_build_object('lig', ortak.lig_durumu(p_oyun)) else '{}'::jsonb end
    -- Sunucu kontrollü bayraklar (6800): {"kapali": ["turnuva", ...], "asgari_surum": "1.0.3", "duyuru": "..."}.
    || jsonb_build_object('bayraklar', coalesce((select ayarlar -> 'bayraklar' from ortak.oyunlar where id = p_oyun), '{}'::jsonb));
end $$;
