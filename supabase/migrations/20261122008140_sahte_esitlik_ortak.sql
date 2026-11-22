-- Sahte Masası SM-4 (kurucu kararı 22 Kasım, puan sürümü 2 ile birlikte): eşit puanlılar aynı sırayı alır; ikincil
-- değer kayıt olarak yazılmaya devam eder ama sırayı belirlemez.
update ortak.oyunlar
   set ayarlar = jsonb_set(ayarlar, '{siralama,esitlik}', '"ortak"')
 where id = 'sahte';
