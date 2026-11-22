-- Göç 8280: yayın öncesi önizleme (kurucu kararı, 22 Kasım). Yayın tarihi kesinleşmeyen oyunlarda günlük, lig, etkinlik,
-- sıralama ve düello canlı sitede herkese kapalı; yalnız test listesindeki hesaplar (kurucu) görür ve oynar.
-- - ortak.oyunlar.ayarlar.yayin: 'onizleme' | 'acik' (yoksa 'acik'). Yayın günü yalnız bu değer 'acik' olur.
-- - ortak.testciler: önizlemede her şeyi gören hesaplar; yalnız servis rolü. Liste canlıda elle doldurulur (göçte kimlik yok).
-- - ortak.etkin_bayraklar(oyun, kullanıcı): ayarlar.bayraklar + önizleme. Test listesinde olmayana kapali listesine
--   ONIZLEME_KAPALI eklenir; testçiye {onizleme, testci, lig_acik} döner. acilis artık bunu döner; dogrula işlevleri
--   ortak-sunucu `ozellikAcik` ile aynı işlevi sorar.
-- ponytail: okuma RPC'leri (siralama, lig_durumu) önizlemede kapatılmadı; halka açık istemci sekmeyi göstermez, skoru yalnız
-- testçi yazabildiği için tabloda yalnız testçi satırı olabilir. Yayın günü temizliği (scripts/yayin-temizligi.ts) onları siler.

create table ortak.testciler (
  kullanici_id uuid primary key references auth.users (id) on delete cascade,
  aciklama text,
  eklendi timestamptz not null default now()
);
alter table ortak.testciler enable row level security;
revoke all on ortak.testciler from public, anon, authenticated;

create function ortak.etkin_bayraklar(p_oyun text, p_kullanici uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  with o as (
    select coalesce(ayarlar -> 'bayraklar', '{}'::jsonb) as b, coalesce(ayarlar ->> 'yayin', 'acik') as y
      from ortak.oyunlar where id = p_oyun
  ), t as (
    select exists (select 1 from ortak.testciler where kullanici_id = p_kullanici) as testci
  )
  select case
    when o.y <> 'onizleme' then o.b
    when t.testci then o.b || '{"onizleme": true, "testci": true, "lig_acik": true}'::jsonb
    else o.b || jsonb_build_object('onizleme', true, 'kapali',
           (select coalesce(jsonb_agg(distinct k), '[]'::jsonb) from (
              select jsonb_array_elements_text(coalesce(o.b -> 'kapali', '[]'::jsonb)) as k
              union select unnest(array['gunluk', 'lig', 'etkinlik', 'siralama', 'duello'])) x))
  end
  from o, t;
$$;
revoke all on function ortak.etkin_bayraklar(text, uuid) from public, anon, authenticated;
grant execute on function ortak.etkin_bayraklar(text, uuid) to service_role;

-- acilis: bayraklar artık önizlemeyi içerir (gövdenin geri kalanı göç 6800 ile aynı).
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
      'profil', md5(concat_ws('|', ortak.bugun(), o.ad, o.kademe, o.profil_gizli, o.desen, od,
                 (select count(*) || ':' || coalesce(max(s.olusturma)::text, '') from ortak.skorlar s
                  where s.oyun_id = p_oyun and s.kullanici_id = u))),
      'oduller', od,
      'haklar', (select md5(coalesce(string_agg(h.hak || '|' || h.durum || '|' || h.guncelleme::text, ',' order by h.hak), ''))
                 from ortak.haklar h where h.oyun_id = p_oyun and h.kullanici_id = u),
      'kayit', coalesce((select k.surum from ortak.kayitlar k where k.oyun_id = p_oyun and k.kullanici_id = u), 0)))
    || case when exists (select 1 from ortak.oyunlar where id = p_oyun and ayarlar ? 'lig')
            then jsonb_build_object('lig', ortak.lig_durumu(p_oyun)) else '{}'::jsonb end
    || jsonb_build_object('bayraklar', ortak.etkin_bayraklar(p_oyun, u));
end $$;
