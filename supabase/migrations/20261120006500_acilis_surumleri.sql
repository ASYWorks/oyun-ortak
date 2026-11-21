-- Açılış ve sürümler (19 Kasım, kurucu: "Kendi profilini her açışta sunucuya sormaya gerek var mı ... aynı mantığı başka
-- yerlere de uygula"). Oyun her açılışta ben, kayıt, ödüller, haklar ve profil için ayrı istek atıyordu. ortak.acilis tek
-- istekte ben'in işini yapar (satır açar, son_gorulme) ve her bilgi için sürüm damgası döner; istemci cihazdaki kopyanın
-- damgası aynıysa o bilgiyi istemez.
--
-- Damgalar oyuncunun kendi küçük satırlarından o an hesaplanır (tetikleyici yok, yazma yok):
--   profil : ad, kademe, gizlilik, desen, skor sayısı ve son skor anı, ödül damgası. Lig sırası ve turnuva en iyi sırası
--            başkalarının skoruyla değişir, damgaya girmez: istemci bunları lig ekranında taze alır.
--   oduller: ödül adı + kazanma anı (ekleme ve silme damgayı değiştirir).
--   haklar : hak + durum + güncelleme (satın alma, iade, devir).
--   kayit  : bulut kaydının sürüm numarası (yoksa 0).
-- Damga yalnız oturumdaki kullanıcının satırlarından; başka hesabın bilgisi dönmez. Hesap değişince istemci önbelleği
-- hesap kimliğine göre ayırır (ben.kimlik değil; istemci kendi oturumunu bilir).

create function ortak.acilis(p_oyun text) returns jsonb
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
            then jsonb_build_object('lig', ortak.lig_durumu(p_oyun)) else '{}'::jsonb end;
end $$;

revoke execute on function ortak.acilis(text) from public, anon, authenticated;
grant execute on function ortak.acilis(text) to authenticated;

-- ben her açılışta son_gorulme yazıyordu (açılış başına bir satır güncellemesi). son_gorulme yalnız 90 günlük misafir
-- temizliğinde kullanılır: saatte en çok bir kez yazılır. Yanıt aynı.
create or replace function ortak.ben(p_oyun text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); o ortak.oyuncular; p ortak.profiller;
begin
  insert into ortak.profiller (kullanici_id) values (u) on conflict do nothing;
  insert into ortak.oyuncular as x (oyun_id, kullanici_id) values (p_oyun, u)
    on conflict (oyun_id, kullanici_id) do update set son_gorulme = now()
      where x.son_gorulme < now() - interval '1 hour'
    returning * into o;
  if o.kullanici_id is null then
    select * into o from ortak.oyuncular where oyun_id = p_oyun and kullanici_id = u;
  end if;
  select * into p from ortak.profiller where kullanici_id = u;
  return jsonb_build_object(
    'ad', o.ad, 'ad_otomatik', o.ad_otomatik, 'ad_degisti', o.ad_degisti,
    'kademe', o.kademe, 'seviye_puani', o.seviye_puani, 'baglama_odulu', o.baglama_odulu,
    'yas_onay', p.yas_onay, 'anonim', ortak.anonim());
end $$;
