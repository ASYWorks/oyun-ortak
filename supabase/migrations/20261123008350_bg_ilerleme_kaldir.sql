-- Göç 8350: Beat Greedy İlerleme tablosu kaldırıldı (kurucu, 23 Kasım; BG K139). Seviye paketleri çözüm taşıdığı için seviyeler
-- alıştırmadır (O28); seviye sıralaması yok. İstemci f132c98'den beri submit_level göndermiyor, board_levels okumuyor.
-- 1. adım (bu göç): sıralama görünümü ve kayıt işlevi silinir, seviye kayıtları boşaltılır.
-- 2. adım (sonra): sezgi.level_verified tablosu, BG istemcisi "verilerimi indir"den o okumayı kaldırınca düşürülür;
--    canlı istemci (f132c98) hâlâ okuduğu için tablo şimdi silinirse veri indirme bozulur.
-- submit_level uç işlevi canlıdan ve testten ayrıca silindi (supabase functions delete).

drop view if exists sezgi.board_levels;
drop function if exists sezgi.record_level(uuid, text, integer, integer, double precision, numeric);
delete from sezgi.level_verified;
