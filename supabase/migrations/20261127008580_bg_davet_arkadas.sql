-- Göç 8580 (BG-15, kurucu K143): Beat Greedy davet ligleri arkadaş tablosuna dönüşür. Aynı davet liginin üyeleri
-- ortak.arkadasliklar'da karşılıklı arkadaş olur (oyun 'sezgi'; ortak oyuncu satırı olanlar). Lig tabloları silinmez
-- (istemci geçince ayrı göçle kaldırılır). Tekrar çalışması zararsız: BG istemcisi arkadaş tablosuna geçtiği gün
-- bayraklar.kapali'ya 'lig' eklenir (7400: yeni lig kurma ve katılma kapanır) ve aynı sorgu bir kez daha çalıştırılır.
-- ponytail: 100 arkadaş sınırı taşımada uygulanmaz (canlıda lig başına birkaç kişi); çok büyürse sınır ekle.

insert into ortak.arkadasliklar (oyun_id, kullanici_id, arkadas_id)
select distinct 'sezgi', a.user_id, b.user_id
from sezgi.league_members a
join sezgi.league_members b on b.league_id = a.league_id and b.user_id <> a.user_id
where exists (select 1 from ortak.oyuncular o where o.oyun_id = 'sezgi' and o.kullanici_id = a.user_id)
  and exists (select 1 from ortak.oyuncular o where o.oyun_id = 'sezgi' and o.kullanici_id = b.user_id)
on conflict do nothing;
