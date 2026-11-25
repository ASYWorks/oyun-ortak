# Görev: portföy önerilerini değerlendir ve haklı olanları uygula (25 Kasım)

Kurucu kararı: 219 öneriden 12'si yapıldı. Kalanları her oyun kendi oturumunda değerlendirir. Mantıklı ve haklı olanlar kesinlikle uygulanır.

## Oyunun öneri listesi

Klasör: `C:/Users/alise/Documents/Codex/2026-11-23/cl/outputs/oyun-altyapisi-inceleme/`

| Oyun | Dosya ve bölüm | Ayrıntılı rapor |
|---|---|---|
| Mahalle Dönüşümü | `portfoy-iyilestirme-01-06.md` "01" | `portfoy-01-mahalle-donusumu.md` |
| Kapı Ustası | `portfoy-iyilestirme-01-06.md` "02" | `portfoy-02-kapi-ustasi.md` |
| Beat Greedy | `portfoy-iyilestirme-01-06.md` "03" | `portfoy-03-beat-greedy.md` |
| Ense Nasıl Olsun? | `portfoy-iyilestirme-07-12.md` "10" | `portfoy-10-ense-nasil-olsun.md` |
| Sahte Masası | `portfoy-iyilestirme-07-12.md` "11" | `portfoy-11-sahte-masasi.md` |
| Halka Kelime | `portfoy-iyilestirme-13-17.md` "17" | `portfoy-17-halka-kelime.md` |
| Remzle | `portfoy-iyilestirme-18-23.md` "18" | `portfoy-18-remzle.md` |
| İfade Katı | `portfoy-iyilestirme-18-23.md` "20" | `portfoy-20-ifade-kati.md` |
| Sticky Ten | `portfoy-tur-5-ayrintili-iyilestirmeler.md` "24" | `portfoy-24-sticky-ten.md` |
| Koz Hesabı | `portfoy-tur-5-ayrintili-iyilestirmeler.md` "25" | `portfoy-25-koz-hesabi.md` |
| Ezber Bozan | `portfoy-tur-5-ayrintili-iyilestirmeler.md` "27" | `portfoy-27-ezber-bozan.md` |
| Hop Koala | `portfoy-37-hop-koala.md` | `hop-koala-yayin-hazirligi.md` |

Yapılmış olanları `bulgu-uygulama-takibi.md` dosyasında gör, onları yeniden yapma.

## Her öneri için

1. Güncel kodla karşılaştır. Sonuç dört türden biridir: **yapılmış** (kanıt dosya:satır), **uygula**, **uygulama** (gerekçe: yanlış ölçüm, oyun kararıyla çelişiyor, maliyet kazançtan büyük), **kurucuya sor**.
2. Kurucuya yalnız şunlar sorulur: silme, para ve fiyat, ücretsiz/ücretli kapsamı, oyun adı, kural istisnası, oyunun ana kuralını değiştiren tasarım. Gerisine oturum kendisi karar verir.
3. "Uygula" denenleri önce testini yazarak uygula. Sunucu, güvenlik ya da çok dosyalı tasarım gerektiren iş Sonnet oturumunda başlatılmaz: "opus gerekir" diye işaretlenir.
4. Ortak kütüphane ya da göç gerekiyorsa kendin yazma, isteği `oyun-ortak/ISTEKLER.md`'ye ekle.
5. Ölçüm gerektiren iddialarda (dokunma alanı, hız) önce ölç. Halka'da incelemenin görünen kutuyu ölçtüğü çıktı, gerçek dokunma alanı yeterliydi.

## Çıktı

- Oyunun deposunda `docs/PORTFOY_KARAR.md`: tablo (öneri, karar, gerekçe ya da kanıt, durum).
- Kurallar: oyunun CLAUDE.md ve DENETIM.md dosyaları, açık dil (M1). Commit'te yalnız değişen dosyalar eklenir, `git add -A` kullanılmaz. Yayın `yayinla.mjs` ile yapılır.
- Oyun-ortak oturumuna rapor en çok 5 satır olsun: yapılmış / uygulandı / uygulanmadı / kurucuya sor sayıları, yayın, opus gereken işler.

## Kapsam dışı

- El Bitir, Kayan Yük ve Kelime Köprüsü taşınırken değerlendirilir.
- Henüz oyun hâline gelmemiş 27 fikrin önerileri, kurucu prototip seçimini yapınca ele alınır.
