-- Göç 8270: Mahalle Dönüşümü haftalık lig ayarı (Mahalle oturumunun tanımı, 22 Kasım). Kademeler inşaat sırası, 30 kişilik
-- grup, haftanın en iyi 5 günü, eşitlikte ikincil (aktif süre). lig_kapat floor(n × oran) kullanır: 30 kişide 0,24 → ilk 7
-- çıkar, 0,17 → son 5 iner. Lig arka planda dolar; oyuncuya görünmesi bayraklar.lig_acik ile (açma eşiği haftada en az 3 gün
-- Beşli bitiren 300 oyuncu; PERIYODIK). Haftalık kapanış ortak cron'u (ortak-lig-kapat) bütün ligli oyunları kapsar.

update ortak.oyunlar
   set ayarlar = jsonb_set(ayarlar, '{lig}',
         '{"kademeler":["Kazı","Temel","Kolon","Kat","Çatı","Sıva","Boya","Anahtar"],"grup_boyu":30,"cikis_orani":0.24,"inis_orani":0.17,"en_iyi_gun":5,"esitlik":"ikincil","bant_genisligi":0}'::jsonb, true)
       || jsonb_build_object('bayraklar', coalesce(ayarlar->'bayraklar', '{}'::jsonb) || '{"lig_acik": false}'::jsonb)
 where id = 'mahalle';
