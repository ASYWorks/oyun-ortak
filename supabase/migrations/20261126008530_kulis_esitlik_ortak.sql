-- Göç 8530: Kulis'te eşit puan aynı sırayı alır (kurucu 26 Kasım, Fable incelemesi bulgu 7; Koku İzi ile aynı gerekçe):
-- süre sıralamaya ve lige girmez. dogrula-kulis ikincil göndermeye devam edebilir, ortak eşitlikte yok sayılır.
update ortak.oyunlar
   set ayarlar = jsonb_set(jsonb_set(ayarlar, '{siralama,esitlik}', '"ortak"'), '{lig,esitlik}', '"ortak"')
 where id = 'kulis';
