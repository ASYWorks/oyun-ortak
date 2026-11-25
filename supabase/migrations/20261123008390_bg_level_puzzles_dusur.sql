-- Göç 8390: Beat Greedy eski seviye tablosu (kurucu 23 Kasım "silinsin"). sezgi.level_puzzles yalnız submit_level içindi; uç işlev
-- 8350'de, istemcideki ve depodaki son kalıntılar BG 67c300f'te kaldırıldı (levelgen upload-levels dahil). Seviyeler oyunun
-- paketlerinde; tablo gerekirse levelgen ile yeniden kurulur. Canlıda 53.276 satır, 66 MB; yedek 22 Kasım 16:07Z'de.
drop function if exists sezgi.level_for_submit;
drop table if exists sezgi.level_puzzles;
