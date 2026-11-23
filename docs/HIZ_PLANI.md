# Hız planı (23 Kasım 2026)

Kurucu: "Tüm oyunlarda tepkilerin, ilk açılışların ve geçişlerin hızlı olması çok önemli." Kaynaklar: canlı ölçüm (Opus 5.5; 12 site,
Yavaş 4G + 4× CPU, 3 koşu medyanı), paket incelemesi (Fable 5.2), bağımsız görüş (GPT Astra). Ham veri ve raporlar oturum çalışma
alanında (`hiz/olcum-raporu.md`, `paket-raporu.md`, `astra-son.txt`); özet aşağıda.

## Bugün (soğuk açılış, ana etkileşim öğesi görünür olana kadar)

| Oyun | Hazır | LCP | İlk JS (gz) | Başlıca neden |
|---|---|---|---|---|
| Beat Greedy | 11,0 sn | 1,3* | 1.136 KB | tek 1 MB paket, iki 1+ sn uzun görev, canvaskit.wasm 8 MB; **yazı tipi yolları bozuk (webde hiç yüklenmiyor)** |
| Remzle | 5,6 | 5,6 | 185 | Levels açılışında 2,2 sn tek hesaplama; 17 kritik istek; önbellek başlığı yok |
| Ezber | 2,5 | 4,8 | 134 | 10 karakter görseli (470 KB) aynı anda; menü bayrak cevabını bekliyor |
| Halka | 3,2 | 1,9 | 141 | gün dizini → seviye JSON zinciri |
| Koz | 3,0 | 3,0 | 199 | ilk boyama bayrak cevabını bekliyor; kod bölme yok |
| Sticky | 2,9 | 3,3 | 213 | tek parça; SVG filtreli arka plan + 565 ms görev |
| Ense | 2,6 | 2,6 | 137 | bayrak beklemesi; özetsiz app.js |
| Kapı | 2,5 | 2,8 | 109 | 3 sn bayrak beklemesi tavanı; önbellek başlığı yok |
| İfade | 2,3 | 2,5 | 235 | seviye verisi pakette; önbellek başlığı yok |
| Sahte | 2,1 | 3,5 | 112 | takvim → bölüm zinciri; yazı tipleri 223 KB |
| Mahalle | 2,0 | 2,0 | 117 | (şablon: kod bölme, SW, immutable, preconnect var) |
| Hop Koala | 1,4 | 1,4 | 164 | ön önbellek sw.js 614 KB |
\* BG LCP kapak görseli; gerçek menü 11 sn.
Geçişler çoğunlukla 25–160 ms; 250 ms üstü: Halka seviye listesi 312, Kapı seviye haritası 312, İfade Başla 296, Mahalle Ayarlar 280.

## Ana karar
Kazanç sırası: **(1) ilk ekranın ağ beklemesini kaldırmak** (1,5–3 sn), **(2) uzun ana iş parçacığı görevleri**, **(3) önbellek**, **(4) paket küçültme**.
Supabase ince istemcisi ölçülmüş −28 KB gzip (yavaş 4G'de ~140 ms); değerli ama ilk iş değil, önce bir oyunda pilot.

## Faz 1: hızlı ve düşük riskli (oyun oturumları, oyun başına 1 yayın)
1. **İlk ekran ağı beklemesin** (Koz, Ezber, Kapı, Ense, Sahte; Halka'nın dizin zinciri): yerel menü hemen çizilir; bayrak/oturum
   arkada gelir. ÖG-58 korunur: bayrak bilinmezken çevrimiçi özellikler kapalı, gelince yeniden çizim. Saklı son bayrak kullanılabilir
   (yalnız sunucu cevabından saklanır; sunucu kapalı işlemi zaten reddeder).
2. **Beat Greedy yazı tipi hatası**: `/assets/__________Projeler/...ttf` yolları HTML dönüyor; düzelt, açılış ekranını yazı tipine bağlama.
3. **Önbellek başlıkları**: özetli dosyalara `public, max-age=31536000, immutable` (Remzle, Kapı, İfade, Hop Koala); Ense ve Ezber önce
   özetli dosya adına geçer. HTML ve sw.js yeniden doğrulanır.
4. **Ezber**: ilk ekranda görünmeyen karakter görselleri ertelenir, görünenler küçültülür (−250–400 KB).
5. **Remzle**: Levels açılışındaki 2,2 sn hesaplama azaltılır (yalnız gereken seviyeler, kalan iş dilimlenir).
6. **Bayrak çift çağrısı** (Ense, Sahte) tekilleşir.

## Faz 2: ortak kütüphane ve daha büyük oyun işleri
7. **Çevrimiçi istemci ilk çizimden sonra** (Halka deseni): `createClient` ilk pakette değil, menüden sonra yüklenir (−58–66 KB kritik
   yoldan). Ortak kütüphanede yardımcı + ENTEGRASYON güncellemesi.
8. **İnce Supabase istemcisi** (`@oyun/ortak/istemci`): Mahalle'de pilot; storageKey, PKCE, functions hata biçimi birebir korunur; e2e hesap akışlarıyla doğrulanınca diğerleri.
9. **Yazı tipi alt kümeleri** (Sahte, Ezber, İfade; Türkçe glif denetimiyle), **İfade seviye verisi ayrı dosyalara**, **Koz/Sticky/İfade
   kod bölme** (kritik JS zinciri derinliği ≤2), **Koz SW ön önbelleği** kabukla sınırlı (bugün 181 dosya 3 MB).
10. **oyun_bayraklari** isteği: şimdilik POST kalır; tasarım seçenekleri (aynı kökenli uç, GET RPC, kısa kenar önbelleği) ÖG-58 ile
    birlikte ayrıca ölçülür. Sticky SVG filtresi A/B ölçülür.

## Faz 3: Beat Greedy ve kurallar
11. **Beat Greedy**: (a) yazı tipi + teşhis (uzun görevlerin çağrı yığını, wasm'ı hangi ekranın istediği); (b) motor, CanvasKit ve sesler
    menü girişinden çıkar, menü görselleri görünenle sınırlanır; Expo'nun gerçekten ayrı parça ürettiği doğrulanır; ara hedef ilk JS
    ≤400–500 KB, menü ≤4–5 sn, sonra ≤3 sn. Hedef kaçarsa yalnız menü + tek sahne Vite prototipiyle ölçülür; yeniden yazım kararı ondan sonra.
12. **Hız kuralları** OYUN_DENETIMI'ne (taslak H1–H13, Astra düzeltmeleriyle): menü kullanılabilir ≤3 sn, LCP ≤2,5 sn, TBT ≤150 ms
    (aynı profil); geçişte ilk geri bildirim ≤100 ms, yerel ekran ≤200 ms; ilk JS 120 KiB (çatısız/Preact) / 150 KiB (React) başlangıç
    hedefi; kritik yazı tipi ≤60 KiB, 0–2 preload; görünür görseller toplam ≤150 KiB; özetli dosyalar immutable; SW zorunlu değil, varsa
    ön önbellek ≤700 KiB; başarısız varlık isteği 0; ÖG-58 ihlali 0.
13. **Ölçüm ortaklaşır**: canlı ölçüm betiği `scripts/hiz-olc.mjs` olarak oyun-ortak'a alınır; Pazar listesinde ayda bir (ve büyük
    yayından sonra) bütün sitelerde koşulur, sonuç tabloyla karşılaştırılır.

## Sıra ve bellek
Oyun oturumları bellek durumuna göre 2–3'er açılır (kurucu kuralı). Faz 1 sırası: Beat Greedy (hata) + Koz, sonra Ezber + Remzle,
sonra Kapı + Ense + Sahte, sonra Halka + İfade + Hop Koala (önbellek). Faz 2'nin ortak kütüphane işi oyun-ortak'ta paralel.

## Durum (23 Kasım akşam; yarıda kalırsa buradan devam)
Akış: oyun Faz 1'i yayınlar → oyun-ortak canlıda yeniden ölçer (yöntem yukarıda; betik oturum çalışma alanında `hiz/olc.mjs`, kalıcısı
`scripts/hiz-olc.mjs` olarak alınacak) → ölçüm iyiyse ve oturum açıksa Faz 2 aynı oturuma verilir → bitince oturum kapatılır.
| Oyun | Faz 1 | Faz 2 | Not |
|---|---|---|---|
| Beat Greedy | yayında 39541ef (yazı tipi düzeldi, wasm immutable) | Faz 3 verildi (karo görselleri, wasm LAZY, asyncRoutes, tek dil, useFrameSize) | ara hedef ilk JS ≤400–500 KB, menü ≤4–5 sn |
| Koz | yayında 5e9d79e (FCP 2,5 → 1,0 sn; SW kabuk 22 dosya 1,1 MB) | verildi (React.lazy kod bölme, istemci dinamik import) | sonra dil dosyası görevi |
| Ezber | yayında 4cad6b8 (LCP 7,3 → 3,2 sn, menü 3,3 sn) | verildi (oturum/hak beklemesi, istemci dinamik import) | dil hazırlığı yayında (8784a50) |
| Kapı | verildi (menü beklemesi, immutable, harita geçişi) | — | dil dosyası işi de sürüyor |
| Remzle, Ense, Sahte, Halka, İfade, Hop Koala | sırada | — | 2–3'er oturum |
| Mahalle | şablon | ince istemci pilotu | dil dosyası görevi kurucu çalışması bitince |
Ortak kütüphane (oyun-ortak): çevrimiçi istemciyi ilk çizimden sonra yükleyen yardımcı + ince istemci (Faz 2) henüz başlamadı.
