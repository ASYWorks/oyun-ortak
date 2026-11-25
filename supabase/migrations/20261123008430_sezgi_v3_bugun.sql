-- Göç 8430: Beat Greedy puan sürüm 3 kapısı 30 Kasım'dan Pazartesi 23 Kasım'a alındı (kurucu 23 Kasım: "beklemeye gerek yok,
-- sıralamalar kapalı zaten"; önizlemede sıralama yalnız testçiye açık). İstemci motorunun POINTS_V3_FROM'u da aynı güne çekilir
-- (sezgi). Kapıdan önceki skorlar yeniden hesaplanmaz (ADIL_PUAN §3.2); bugünün kapıdan önceki birkaç testçi skoru sürüm 2 kalır,
-- yayın günü temizliği onları zaten siler.
update sezgi.puan_surumleri set gecerli = '2026-11-23' where formul = 3;
