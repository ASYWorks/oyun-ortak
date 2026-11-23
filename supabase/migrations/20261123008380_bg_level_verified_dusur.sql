-- Göç 8380: Beat Greedy İlerleme tablosu, 2. adım (kurucu 23 Kasım "tabloyu silelim"; 8350'nin devamı). BG istemcisi a01767e'den
-- beri "verilerimi indir"de level_verified okumuyor. Tablo 8350'de boşaltılmıştı; testte ve canlıda 0 satır, bağımlı görünüm ya da
-- işlev yok (pg_depend ve prosrc 23 Kasım'da denetlendi).
drop table if exists sezgi.level_verified;
