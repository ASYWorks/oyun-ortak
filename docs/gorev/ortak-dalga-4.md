# Görev: ortak dalga 4 (kurucu kararları 26–27 Kasım 2026)

Bütün aktif oyunlar uygular (Sticky Ten ve Hop Koala yalnız uygun maddeleri). Kurucu kararı (27 Kasım): **dalga hâlinde, sırayla; yapı işleri de bu dalgada.** Oturum her maddeyi `docs/DENETIM.md`'de kanıtla işaretler; kurucu kararı gereken yerde seçenekli sorar (öneri ilk); ağır iş için oyun-ortak oturumundan sıra ister; yayın kurucu onayıyla. Takip: `docs/takip/dalga-4.md`.

Kaynaklar: `_ortak/OYUN_DENETIMI.md` (A5, A22–A35, M1, 3d Z1–Z9), `_ortak/ADIL_PUAN.md` §0, `_ortak/ARAYUZ_KURALLARI.md`, `oyun-ortak/docs/arastirma/` (arayuz-ve-uretim-kararlari, seviye-iskeleti, puan-ve-siralama).

## A. Hızlı ve mekanik (Sonnet yeter)
1. **Dalga 3:** kök CSS'te `touch-action: manipulation` (A5); oyuncu metninde şapkalı harf 0 (M1); oklu sekme/sayfa/kart dizilerinde parmakla kaydırma (A22). Ayrıntı `docs/gorev/ortak-dalga-3.md`.
2. `@oyun/ortak` son sürüm (v0.24.0 ya da üstü).
3. Para tarafsızlığı testi: hak sahibi ve olmayan hesap aynı girdide aynı `puan` ve `ayrinti` (ADIL_PUAN §0.4).
4. Kişisel ad ve kişisel yol hiçbir dosyada yok; commit kimliği ASYWorks.

## B. Ekran ve kimlik (Opus)
5. **A27 ilk açılış:** doğrudan öğretici bulmaca, kaybedilemez, ilk hamle ≤3 dokunuş ve ≤10 sn; ana ekran ondan sonra.
6. **A28 ana ekran:** tek birincil eylem (Oyna/Devam), ayarlar ve hesap köşede.
7. **A29 alt çubuk:** ≤2 hedefte yok, 3–4 hedefte var, en çok 5; oyunda gizli.
8. **A30 geri tuşu:** ARAYUZ'da geri tablosu; oyunda geri sessizce kaydeder; tarayıcı geri önce açık pencereyi kapatır (history.pushState/popstate).
9. **A24–A25 kimlik:** yasak listesi eki (her başlıkta ikon, tek kenarı renkli kart, hep aynı hap düğme, kalıp coşku metni, tek süre/eğri); imza biçim ARAYUZ'da tek cümle.
10. **A32–A35 his:** his tablosu, hareket bütçesi, süre/eğri token'ları, hareket azaltma karşılığı; `@oyun/ortak/his` kullanılabilir; kütüphane gerekirse GSAP ya da Rive.
11. **A23 sanat yönetmeni paftası:** ana ekranlar ve ödül anı tek paftada, kurucu onaylar.

## C. Yapı (Opus; içerik ve puan sürümü değişir, plan önce kurucuya)
12. **Seviye iskeleti (3d Z1–Z8):** `SEVIYE_YAPISI.md`'de X (5–8) × Y (60–400), toplam ≥1.000 ya da onaylı istisna; 3–5 seviyelik Başlangıç; her yeni kurala 2–3 tanışma seviyesi; 20'lik bölümlerde testere dişi (ilk 3 kolay, 10 tepe/11 nefes, 19 nefes/20 kapı, art arda en çok 2 zor, K5'ten sonra −2 kademe) ve otomatik test; ilk 100 seviyede ≥3 yeni öğe; zorluk oyuncuya görünür. Mevcut içerik yeniden sıralanır; kayıt ve ilerleme göçü planlanır.
13. **Ortak modlar (Z9):** günlük, seri sayacı (kaçırılan güne yumuşak kural), sonucu paylaşma, arşiv, haftalık lig, etkinlik.
14. **Puan ve sıralama (ADIL_PUAN §0):** yeni puan sürümü: süre cömert bant (medyan×2, aşım en çok −20), hız ödülü yok; eşitlik bozucu oyun oyun, süreyse görünür (§6); genel günlük tablo yerine arkadaş tablosu + 20–30 kişilik lig (paket hazır olunca); ücretliye rekabete girmeyen ek arşiv/alıştırma; bot raporu tavan yığılması ve hileci oranı.

## Sıra
Önce paket işleri (oyun-ortak: arkadaş tablosu, lig grubu 20–30, süzülmüş lig BG-12/RZ-9). Oyunlar: Halka Kelime, Sahte Masası, Beat Greedy → Kelime Köprüsü, El Bitir, Kayan Yük, Kapı Ustası, Koz Hesabı, Mahalle Dönüşümü, İfade Katı, Ezber Bozan, Ense, Remzle → Kulis, Koku İzi (geliştirmede, baştan uyar). Aynı anda en çok 2–3 oyun.

## Rapor
A, B, C bitince ayrı ayrı en çok 5 satır.
