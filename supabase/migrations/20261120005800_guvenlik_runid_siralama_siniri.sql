-- Güvenlik kontrolü (19 Kasım, performans değişikliklerinin güvenlik incelemesi; tests/sunucu/guvenlik.test.ts).
-- 1) skor_yaz: run_id tabloda benzersiz ama kullanıcıya bağlı değildi. B, A'nın runId'siyle gönderirse A'nın skoruna 'tekrar'
--    alıyor (skor kimliği sızıyor, A'nın yeniden gönderimiyle karışıyordu). Artık başkasının runId'si 'run_id' döner, yazmaz.
-- 2) ortak.siralama girişsiz de açık ve her çağrıda günün bütün skorlarını sıralıyor; hız sınırı yoktu (pahalı sorgu
--    sınırsız). Dakikada 120; girişliye kimlikle, girişsize IP ile (ortak ağdaki girişsizler paylaşır; oyuncular girişli).
--    hiz_siniri yazdığı için işlev artık stable değil.

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
  if v_id is not null then return jsonb_build_object('durum', 'tekrar', 'id', v_id); end if;
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
  return jsonb_build_object('durum', 'yeni', 'id', v_id);
end $$;

create or replace function ortak.siralama(p_oyun text, p_tur text, p_donem text, p_ilk integer default 10, p_cevre integer default 3)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a jsonb;
  esik int;
  ben uuid := auth.uid();
  r jsonb;
  h json := nullif(current_setting('request.headers', true), '')::json;
begin
  -- Dakikada 120 (girişliye kimlikle, girişsize IP ile; servis rolü sınırsız). Her çağrı günün bütün skorlarını sıralar.
  if auth.role() is distinct from 'service_role' and not ortak.hiz_siniri('siralama:' || coalesce(ben::text, h ->> 'cf-connecting-ip',
       split_part(h ->> 'x-forwarded-for', ',', 1), 'anon'), 120, 60) then
    raise exception 'cok_istek' using errcode = '54000';
  end if;
  select coalesce(ayarlar -> 'siralama', '{}') into a from ortak.oyunlar where id = p_oyun;
  if not found then raise exception 'oyun_yok'; end if;
  esik := coalesce((a ->> 'dagilim_esigi')::int, 50);
  p_ilk := least(greatest(p_ilk, 1), 100);
  p_cevre := least(greatest(p_cevre, 0), 10);

  with s as (select * from ortak.sira_listesi(p_oyun, p_tur, p_donem)),
  t as (select count(*)::int as c from s),
  b as (select sn, sira from s where s.kullanici_id = ben)
  select jsonb_build_object(
    'toplam', t.c,
    'kapandi', exists (select 1 from ortak.oduller od where od.oyun_id = p_oyun
                         and od.kaynak = p_tur || ':' || p_donem and od.odul like 'sira:%'),
    'ben', (select jsonb_build_object('sira', b.sira,
              'ust_yuzde', case when t.c >= esik then ceil(100.0 * b.sira / t.c) end) from b),
    'satirlar', coalesce((
      select jsonb_agg(jsonb_build_object('sira', s.sira, 'ad', o.ad, 'puan', s.puan, 'ikincil', s.ikincil, 'profil', o.profil_id,
                                          'ben', coalesce(s.kullanici_id = ben, false)) order by s.sn)
      from s left join ortak.oyuncular o on o.oyun_id = p_oyun and o.kullanici_id = s.kullanici_id
      where s.sn <= p_ilk or exists (select 1 from b where abs(s.sn - b.sn) <= p_cevre)), '[]'::jsonb))
  into r from t;
  return r;
end $$;
