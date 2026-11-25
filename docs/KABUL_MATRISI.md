# Kabul matrisi durumu (25 Kasım 2026)

Kural hâline geldi: OYUN_DENETIMI 3c (K1–K10).

Kaynak: Codex incelemesi `uc-senaryo-test-matrisi.md` (23 Kasım). Bu belge her satırın hangi testle kapandığını ve hangisinin
oyunlarda açık olduğunu tutar.
- **Ortak:** oyun-ortak testleri (`npm test`, `npm run test:sunucu`). 25 Kasım'da 84 birim ve 165 sunucu testi geçti.
- **Oyun:** her oyunun kendi istemci e2e'si (yayinla.mjs `e2e`).

## Kapalı (ortak test)

| Matris satırı | Test |
|---|---|
| Normal oyuncu / testçi, yayın öncesi arşiv; önizlemede kapalı özellik | `onizleme`, 8320 BG önizleme, "arşiv yalnız hakla (ya da testçiye) ve yalnız geçmiş gün" |
| Günlük açık, sıralama kapalı: skor yazılmaz | önizleme ek kuralları (göç 8360), siralama testleri |
| Kapanmış gün, sunucu saati esas | "kapanmış güne gönderim reddedilir (sunucu saati esas)" |
| Aynı istek iki kez / yanıt kayboluyor: tek skor | "aynı runId eşzamanlı 5 kez … tek skor" |
| Nabız gecikmesi, duraklama | 8420 nabız, "nabız: süre yalnız ekrandayken birikir", "nabız durdur" |
| Eşitlik, lig haftası kapanışı | "tablo: eşit puana aynı sıra", lig testleri (Koz, Ezber, Mahalle, Halka HK-13) |
| A'nın işi B'nin oturumuyla sürmez | D02 kuyruk testleri, MD-24 (göç 8440), "A, B'nin kaydını … okuyamaz" |
| Web devri kesintisi, yanıt kaybı, tekrar | D03 istemci testleri + göç 8460 makbuz; "aynı hedefe eş zamanlı iki devir" |
| Hesap silme, oyun oyun ayrı | "silme: hesaplar oyun oyun ayrı", "silip aynı gün yeniden açan" |
| Kuyrukta kalıcı ret, sonraki kayıtları engellemez | "gönderim kuyruğu", 426 ret; 7 günden eski kayıt düşer (v0.23.1) |
| Ödeme: eşzamanlı olay, ters sıra, eski iade | göç 8450 testi |
| Ödeme: bilinmeyen ürün, başka oyunun hakkı | "webhook …", "TRANSFER: yalnız gönderen uygulamanın oyunundaki haklar" |
| Ölçüm kuyruğu, izin kapanıp açılıyor | D09 olcum testleri |
| Yayın adımlarında kesinti, kuru koşu | yayinla.mjs taklit senaryoları (Codex), 25 Kasım'da 5 gerçek yayın |
| Yarım yedek başarı sayılmaz, son iyi yedek | yedek.sh (D10), 25 Kasım gerçek test koşusu |
| Panel notu oturuma ulaşır | 25 Kasım uçtan uca: oyun-test notu → Ense oturumu "alındı" → yapıldı |

## Oyunlar: K1–K10 durumu

Ölçütler OYUN_DENETIMI 3c'de (kurucu 25 Kasım: bütün oyunlarda ortak; taşınan ve yeni oyunlar da geçer). ✓ geçti (eski kodda hata varsa düzeltildi), – yok (karşılığı yok, nedeni oyunun DENETIM'inde), boş = sırada.
Push ve yayın her oyunun kendi oturumunda.

| Oyun | K1–K3 bayrak | K4 | K5 | K6 | K7 | K8 | K9 | K10 | Not |
|---|---|---|---|---|---|---|---|---|---|
| Halka | ✓ 0bb13b5 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | 58ec5ee: K5, K6, K7 hataları düzeldi; 3 e2e yarışı (ÖG-57) giderildi |
| Beat Greedy | ✓ 1aff480 | ✓ | – | ✓ | – | ✓* | ✓ | ✓ | 4e8fc3b: K4, K6 hataları düzeldi; K5 yok (ad seçmeden başlamaz), K7 yok (satın alma kapalı); *K8: ücretli seviyeler pakette, satın alma açılmadan korumalı kovaya taşınacak |
| Sticky Ten | ✓ 57c5d4a | ✓ | – | ✓ | ✓ | ✓ | ✓ | ✓ | 9a1b0cf, Pages 929c4da5, Render protokol=1: K7 hatası, K8 eksik düzeldi; K5 yok (ad_gerekli yolu yok) |
| Hop Koala | | | | | | | | | çevrimiçi bayrak yok; K7 (full_unlock) mağaza paketinde |
| Ense | ✓ 5f0df88 | ✓ | ✓ | ✓ | – | ✓ | ✓ | ✓ | 51645a0: K4, K5, K6, K9 (2), K10 hataları düzeldi; K7 kısmen (satın alma bağlı değil) |
| Sahte | ✓ a146f99 | ✓ | ✓ | ✓ | – | ✓ | ✓ | ✓ | 89b9b47, 071c7a1: K5, K6, K9 hataları düzeldi; K7 yok (ücretli hak yok) |
| Remzle | ✓ 46fb65a | ✓ | ✓ | ✓ | – | ✓ | ✓ | ✓ | 338587e: K5, K6, K9 hataları düzeldi; K7 kısmen (ödeme kapalı) |
| Ezber | ✓ 030d02d | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | f75ca33: K6, K7, K9, K10 hataları düzeldi (K10: yanıt kaybında −5 iki kez) |
| Koz | ✓ 537d773 | ✓ | ✓ | ✓ | – | ✓ | ✓ | ✓ | 7cd2368, 37adc75: K6, K9, K10 hataları düzeldi; düello 403 testi geri, sıralama kapalıyken skor yazılmıyor; K7 yok (ödeme ertelendi) |
| Kapı | ✓ (D05, 42d375e) | ✓ | ✓ | ✓ | – | ✓ | ✓ | ✓ | 88b0b7a: K4, K5, K6, K9 hataları düzeldi; K7 yok (satış yok); arşiv sunucuda (hata 4) |
| Mahalle | ✓ 615dbc6 | | | | | | | | 3 hata; hata 2 ve 4 (7825343) |
| İfade | ✓ e7de7f9 | | | | | | | | K2 hatası düzeldi |
