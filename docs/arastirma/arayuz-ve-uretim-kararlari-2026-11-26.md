# Arayüz kimliği, ilk açılış, oyun hissi ve üretim araçları: araştırma ve kurucu kararları (26 Kasım 2026)

Kurucu panel notları 8, 13, 14, 15, 16. İki Opus araştırması (web kaynaklı); kararlar kurucunun.

## Bulguların özü

- **Yapay zekâ izi** yapay zekânın kendisinden değil varsayılanların birleşmesinden gelir: Inter, Tailwind paleti, ortada kahraman alanı ve üç yuvarlak kart, tek kenarı renkli kart, her başlığın yanında ikon, bütün düğmelerin aynı hap biçimi, "Harika iş!" türü ürün dili, her harekette aynı eğri ve süre, oyun alanının menü kartı gibi durması. Stüdyolar kimliği **tek bir imza biçim ve malzemeyle** kurar (Monument Valley'de her seviye bir grafik tasarım işi; Threes'te karakterli sayılar; NYT Games'te ortak sistem + oyun başına tek imza biçim). Kaynaklar görüş yazısı ağırlıklı.
- **İlk açılış:** eğlence hemen gelmeli; Wordle açılınca doğrudan tahta; NYT Games alt sekmeleri 5'ten 3'e indirdi; Material 3'e göre alt çubuk 3–5 hedef için; Android'de "emin misin" yalnız kaybolacak bir şey varken.
- **Oyun hissi:** "Juice it or lose it", "Art of Screenshake"; bulmacada kamera sarsıntısı yerine yerel tepki (yanlışta hücre titrer, doğruda esner, bitişte dalga), ödül anı oyunun malzemesinden. Yalnız `transform`/`opacity` hareketlendirilir (birleştirici iş parçacığında, TBT'ye yük bindirmez); parçacık için tek canvas; Rive/Lottie yalnız karakterli oyunda, ölçerek.
- **Ses:** metin okuma yalnız Hop Koala'da. ElevenLabs ücretli planda üretilen içerik iptalden sonra da ticari; müzik "Indie Game" kapsamında bizim ölçeğimize uyar; alfa/beta özellik çıktısı ticari kullanılmaz (model etiketi üretimden önce kontrol). Suno/Udio hukuki belirsizlik, MusicGen ticari değil, yerel Türkçe TTS uygun değil. Yedek: Stable Audio 3 (yerel, 1 M $ altı ticari; kalite denenmedi), Freesound CC0.
- **Görsel:** Gemini Nano Banana 2 (~0,04–0,08 $, çoklu referans), Recraft (gerçek SVG, ikon/rozet ~0,08 $), FLUX.2 klein (~0,014 $, ucuz deneme), Ideogram (yazılı mağaza görseli), Midjourney (keşif, API yok). Makinede 4 GB ekran belleği: yerel üretim pratik değil. Mağaza görselinde yazı modelle değil sonradan eklenir.

## Kurucu kararları

| Konu | Karar |
|---|---|
| Sanat yönetmeni turu | Her oyunda pafta kurucuya gelir, kurucu onaylar (A23) |
| Geriye dönük uygulama | Yayına en yakın 3 oyunda hemen (Halka Kelime, Sahte Masası, Beat Greedy), ötekilerde bir sonraki büyük sürümde |
| İlk açılış | Doğrudan öğretici bulmaca (kaybedilemez), ana ekran ondan sonra (A27) |
| Alt sekme çubuğu | Hedef sayısına göre: ≤2 hedefte yok, 3–4 hedefte var, en fazla 5; oyun sırasında gizli (A29) |
| Geri tuşu | Sessizce kaydet ve çık; yalnız kaydedilemeyen bir şey kaybolacaksa sor (A30) |
| Kör test | Öneri düzeyinde (A26) |
| Animasyon | Varsayılan CSS ve WAAPI; kütüphane gerekirse profesyonel olan (GSAP ya da karakterli oyunda Rive), tembel yüklenir ve ölçülür (kurucu, aynı gün); oyun-ortak'ta küçük ortak `his` modülü (esneme, titreme, dalga, ses-titreşim eşzamanı) ve parçacık için canvas; görünümü her oyun kendi token'larıyla verir |
| Süs tavanı | Oyun başına, his tablosunda (A32) |
| Ses aracı | ElevenLabs Creator 1 ay: efekt, müzik ve Hop Koala seslendirmesi birlikte üretilir, plan adı ve tarihi lisans dosyalarına, sonra iptal; beta etiketli model kullanılmaz |
| Görsel aracı | Türe göre: illüstrasyon ve doku Gemini Nano Banana 2 (referanslı), ikon/rozet/simge Recraft (SVG), GPT Sol 6.2 yalnız mevcut referanslı seriler (Ezber karakterleri, Koz albümü) |

Kurallar `_ortak/OYUN_DENETIMI.md` A23–A35 ve `ARAYUZ_KURALLARI.md`'ye işlendi.
