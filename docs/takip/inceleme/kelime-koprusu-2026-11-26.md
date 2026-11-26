# Kelime Köprüsü: bağımsız inceleme (Fable 5.2, 26 Kasım 2026)

Commit 3881241, salt okuma. Görev: `docs/gorev/bes-oyun-tamamlama.md` C.

| # | Önem | Kural | Bulgu | Önerilen düzeltme |
|---|---|---|---|---|
| 1 | yüksek | O18, K9, K10 | Gece yarısını aşan günlük deneme sessizce kayboluyor: gunlukVeri.ts:66 siralamali `tarih === bugun()`; teslimEt (:92) ve ipucuIsaretle (:83) buna bağlı; sunucunun 3 saatlik penceresi kullanılamıyor. Oyun.tsx:409 gunTarihi her çizimde Date.now() okuyor | Başlamış deneme varsa gönder; günü açılışta sabitle; saat taklidiyle gece yarısı e2e |
| 2 | orta | A22 (dalga 3) | Kaydırma hareketi yok: parca/ortak.tsx:157–161 Sayfali, Bolumler.tsx:90–92, SayfaliPencere | Ortak yatay sürükleme; DENETIM'e A22 |
| 3 | orta | A5 (dalga 3) | touch-action yalnız button'da (stil/ortak.css:25) | Kök kuralı görev belgesindeki haliyle |
| 4 | orta | O23, O26, ONIZLEME 6 | Kapalı günlük oyun ekranı sol panelinde görünüyor (Cerceve.tsx:183–186, :247); sıfırlama metni "Günlük sonuçlar korunur"; gunlukSunucu.ts "Günlük köprü şu an kapalı." | Bayrağa bağla; kapali'da metin değil ana ekrana dönüş |
| 5 | orta | O13 | Oyunda "puan nasıl hesaplanır" açıklaması yok | Kısa açıklama (formül, ipucu, eşitlik) |
| 6 | orta | M1 (dalga 3) | Ayarlar.tsx:73 "yapay zekâyla" | "yapay zekayla"; yayın zincirine şapka taraması |
| 7 | orta | A18, A2 | CSS'te 20+ sabit px boy (12.5, 13.5 ...); 14 sabit rgba renk | Token ölçeğine indir ya da kurucu onaylı istisna; rgba token |
| 8 | düşük | A14 | Ayarlar.tsx:74 dış bağlantılar oyundan çıkarıyor | Oyun içi pencere |
| 9 | düşük | A24 | Tek kenarı renkli kart (gunluk.css:29 border-left) | İmza biçim işaretiyle değiştir (A24 bir sonraki büyük sürümde zorunlu) |
| 10 | düşük | A1 | ARAYUZ.md'de onay satırı yok | Kurucu onay satırı (A23 paftasıyla) |
| 11 | düşük | H10 | Supabase preconnect yok | Ekle |
| 12 | düşük | O1 | @oyun/ortak v0.23.6 | v0.23.7 |
| 13 | düşük | O25 | CLAUDE.md:86, PORTFOY_KARAR.md:3 kişisel yol | ~/.oyun-ortak/ |
| 14 | orta | Denetim kapsamı | DENETIM'de A22–A35 ve dalga 3 kaydı yok | A22 ve dalga 3 şimdi; A23–A35 bir sonraki büyük sürümde (kurucu 26 Kasım) |

Doğrulanamadı: servis çalışanı skipWaiting ile açık oturumda eski parça indirilemeyebilir; uygulama kimliği com.asyworks.kelimekoprusu ile oyun kimliği kopru farkı; canlı başlıklar, PostHog.
Gerekçeler: P4/K7/P8, P7, H4/H5, S3 geçerli; P3 dürüst (asıl risk içerik onayı); P5, P6, O11, O20 zayıf (canlıda testçiyle tek turda kapanır); O10 yayından önce; S6 yayından önce zorunlu.
Oturumla uyuşmayan: O3 hesap-sil bağlantısı yok; M2 metni farklı; A1 onay satırı yok; A18; A5; O23/O26; O13; K9/K10 gece yarısı sınanmamış.
Genel: sunucu tarafı sağlam; gece yarısı teslim kaybı gerçek hata; dalga 3 eksik. Önce 1–6, sonra canlıda P5/P6/O11/O20 tek turda.
