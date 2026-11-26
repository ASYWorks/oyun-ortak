-- Göç 8510: Kulis ana paketi (KU-5 ek, Aşama 2). Hak paket_tam; RevenueCat uygulaması ve Play ürünü mağaza hazırlığında
-- tanımlanır (ortak.oyunlar.ayarlar.odeme.revenuecat_uygulamalari o zaman doldurulur). Korumalı kova mağaza yaklaşınca.
insert into ortak.urunler (urun, oyun_id, hak) values ('kulis_paket_tam', 'kulis', 'paket_tam') on conflict do nothing;
