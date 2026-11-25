-- Göç 8480: Kayan Yük oyun-ortak'a geçiyor (Vercel'den; canlıda sunucu verisi yok). İstek KY-1.
-- Kurucu kararı (25 Kasım): sıralama türü "yok"; günlük, lig ve sıralama yok. Oyuna özgü şema ve tablo yok:
-- bulut kaydı ortak `kayit_*` işlevleriyle. İstemci hazır olduğu için yayın hemen önizlemede (ONIZLEME §5).
insert into ortak.oyunlar (id, ad, ayarlar) values ('kayan', 'Kayan Yük',
  '{"ad":{"en_az":3,"en_cok":20,"degistirme_gun":30},"yayin":"onizleme","odeme":{"revenuecat_uygulamalari":[]}}')
on conflict (id) do nothing;
