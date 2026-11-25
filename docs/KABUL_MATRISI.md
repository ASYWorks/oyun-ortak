# Kabul matrisi durumu (25 Kasım 2026)

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

## Açık (oyunlarda istemci e2e gerekir)

Oyun oturumları sırayla, 2–3'er yapar. Push ve yayın oyunun kendi oturumunda yapılır.
1. İlk açılışta bayrak yok, ağ yavaş ya da kapalı: menü açılır, doğrulanmamış özellik açılmaz (ÖG-58). Kapı, Ezber, Halka, Sahte ve Remzle'de bayrak e2e'si var; diğerlerinde eklenmeli.
2. Testçi → çıkış → misafir ya da ikinci hesap: önceki hesabın bayrağı ve özel ekranı devredilmez. Kapı D05 dışında denenmedi.
3. Oyun açıkken bayrak kapanıyor: istemci erişilebilir ekrana döner, geç gelen eski cevap ekranı yeniden açmaz.
4. İki sekme ya da iki cihaz, yanıtlar ters sırada: eski yanıt yeni kutuyu değiştirmez.
5. `ad_gerekli` ertesi güne sarkıyor: sonuç doğru güne bağlanır.
6. Cihaz saati ileri ya da geri: istemci sunucu farkını anlaşılır gösterir.
7. Ücretli hak iade edildi, cihazda indirilmiş içerik var: davranış ürün kararıyla uyumlu (Halka korumalı içerik, Remzle).
8. Eski servis çalışanı ve önbellek: günlük cevap ve korumalı içerik yayında görünmez (paket denetimi bunun bir kısmını yapıyor).
