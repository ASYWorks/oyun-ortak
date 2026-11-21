-- İstek sayısı (19 Kasım, kurucu "verimsiz kısımları düzeltelim"; Nano darboğazı istek başına sabit maliyet ve bellek):
-- 1) istek_siniri: Edge Function'lar kullanıcı ve oyun sınırını iki ayrı hiz_siniri isteğiyle denetliyordu; artık tek istek.
--    Kullanıcı sınırı aşılırsa oyun sayacı artmaz (eskisiyle aynı). Yalnız servis rolü.
-- 2) skor_yaz yeni ve tekrar yanıtında oyuncunun sırasını da döndürür (kullanici_sirasi ile aynı nesne): gönderimde ayrı
--    kullanici_sirasi isteği gerekmez (sunucu/mod.ts c.sira bunu kullanır). Eski çağıranlar için yalnız alan eklendi.
-- 3) cron.job_run_details her dakika büyüyordu (günde ~1.700 satır, temizlenmiyordu): 7 günden eskisi her gece silinir.

create function ortak.istek_siniri(p_kullanici_anahtar text, p_kullanici_sinir integer, p_oyun_anahtar text, p_oyun_sinir integer)
returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if not ortak.hiz_siniri(p_kullanici_anahtar, p_kullanici_sinir, 60) then return false; end if;
  return ortak.hiz_siniri(p_oyun_anahtar, p_oyun_sinir, 60);
end $$;
revoke execute on function ortak.istek_siniri(text, integer, text, integer) from public, anon, authenticated;
grant execute on function ortak.istek_siniri(text, integer, text, integer) to service_role;

create or replace function ortak.skor_yaz(
  p_oyun text, p_kullanici uuid, p_tur text, p_donem text, p_puan numeric, p_run_id uuid,
  p_ikincil numeric default null, p_lig_puani numeric default null, p_ayrinti jsonb default null,
  p_bayraklar text[] default '{}', p_seviye_puani integer default null, p_cihaz text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_sahip uuid; hafta date;
begin
  -- Gönderim kimliği kullanıcıya bağlı: başkasının runId'si 'tekrar' saymaz, onun skorunu (id) da göstermez.
  select id, kullanici_id into v_id, v_sahip from ortak.skorlar where run_id = p_run_id;
  if v_id is not null and v_sahip is distinct from p_kullanici then return jsonb_build_object('durum', 'run_id'); end if;
  if v_id is not null then
    return jsonb_build_object('durum', 'tekrar', 'id', v_id, 'sira', ortak.kullanici_sirasi(p_oyun, p_tur, p_donem, p_kullanici));
  end if;
  if exists (select 1 from auth.users where id = p_kullanici and is_anonymous) then
    return jsonb_build_object('durum', 'misafir');
  end if;
  if not exists (select 1 from ortak.oyuncular o where o.oyun_id = p_oyun and o.kullanici_id = p_kullanici
                 and o.ad is not null and not o.ad_otomatik) then
    return jsonb_build_object('durum', 'ad_gerekli');
  end if;

  insert into ortak.oyuncular (oyun_id, kullanici_id) values (p_oyun, p_kullanici)
    on conflict (oyun_id, kullanici_id) do update set son_gorulme = now();
  if p_seviye_puani is not null then
    update ortak.oyuncular set seviye_puani = p_seviye_puani where oyun_id = p_oyun and kullanici_id = p_kullanici;
  end if;

  if p_tur = 'gunluk' and ortak.kurulum_baska_hesap(p_oyun, p_cihaz, p_donem, p_kullanici) then
    return jsonb_build_object('durum', 'cihaz');
  end if;

  insert into ortak.skorlar (oyun_id, kullanici_id, tur, donem, puan, ikincil, lig_puani, run_id, ayrinti, bayraklar)
  values (p_oyun, p_kullanici, p_tur, p_donem, p_puan, p_ikincil, p_lig_puani, p_run_id, p_ayrinti, p_bayraklar)
  on conflict (oyun_id, tur, donem, kullanici_id) do nothing
  returning id into v_id;
  if v_id is null then return jsonb_build_object('durum', 'prova'); end if;

  if p_tur = 'gunluk' and p_lig_puani is not null
     and exists (select 1 from ortak.oyunlar where id = p_oyun and ayarlar ? 'lig') then
    hafta := ortak.iso_hafta(p_donem::date);
    perform ortak.lig_ata(p_oyun, p_kullanici, hafta);
    perform ortak.lig_puani_guncelle(p_oyun, p_kullanici, hafta);
  end if;
  return jsonb_build_object('durum', 'yeni', 'id', v_id, 'sira', ortak.kullanici_sirasi(p_oyun, p_tur, p_donem, p_kullanici));
end $$;

select cron.schedule('ortak-cron-gecmisi', '25 3 * * *', $$delete from cron.job_run_details where end_time < now() - interval '7 days'$$);

-- 4) Halka gönderimi bulmacayı (halka_dogrula_bulmaca / _turnuva) ve deneme kaydını iki ayrı istekle alıyordu; tek istek.
--    Yalnız servis rolü (dogrula-halka); kullanıcı kimliği Edge'de doğrulanmış oturumdan gelir, istemciden değil.
create function public.halka_gonderim_verisi(p_tur text, p_donem text, p_anahtar text, p_kullanici uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'bulmaca', case when p_tur = 'gunluk' then public.halka_dogrula_bulmaca(p_donem::date)
                    when p_tur = 'etkinlik' then public.halka_dogrula_turnuva(p_donem) end,
    'deneme', (select jsonb_build_object('sira', d.sira, 'durum', d.durum, 'bitti', d.bitti, 'olusturma', d.olusturma,
                                         'aktif_ms', d.aktif_ms, 'son_nabiz', d.son_nabiz, 'durak_ms', d.durak_ms)
               from ortak.denemeler d where d.oyun_id = 'halka' and d.kullanici_id = p_kullanici and d.anahtar = p_anahtar))
$$;
revoke execute on function public.halka_gonderim_verisi(text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.halka_gonderim_verisi(text, text, text, uuid) to service_role;
