# Yayın öncesi önizleme (kurucu kararı, 22 Kasım 2026)

Yayın tarihi kesinleşmemiş her oyun canlıda **önizleme** kipindedir. Bu, bütün oyunlar için geçerlidir (Halka, Beat Greedy ve Sticky Ten dahil). Bu kipte halka açık sitede yalnız seviyelerin ücretsiz kısmı (vitrin) açıktır; günlük, lig, etkinlik, sıralama ve düello gizlidir. Kurucunun hesabı test listesindedir ve canlı sitede her şeyi görüp oynar.

## Nasıl çalışır (göç 8280, paket v0.22.0)

| Parça | Ne yapar |
|---|---|
| `ortak.oyunlar.ayarlar.yayin` | `"onizleme"` ya da `"acik"`; alan yoksa `"acik"` sayılır. Oyunun oturumu hazır olunca oyun-ortak oturumu `"onizleme"` yapar. Yayın günü `"acik"` olur. |
| `ortak.testciler` | Önizlemede her şeyi gören hesaplar. Yalnız servis rolü okur. Liste oyun-ortak oturumunda tutulur (şimdilik yalnız kurucu). |
| `hesap.acilis().bayraklar` | Testçi olmayana `onizleme: true` döner; `kapali` listesine `gunluk`, `lig`, `etkinlik`, `siralama`, `duello` eklenir. Testçiye `onizleme: true, testci: true, lig_acik: true` döner; elle kapatılanlar dışında her şey açık. Yayından sonra da testçiye `testci: true` döner (göç 8300): bütün seviyeler her zaman açık. |
| `c.ozellikAcik(ad)` (ortak-sunucu) | `dogrula-<oyun>` aynı kuralı sunucuda sorar: kapalıysa `c.hata(403, "kapali")`. |
| `scripts/yayin-temizligi.ts` | Yayın günü yayından önceki ortak skor, deneme, kurulum ve lig satırlarını siler (yalnız testçiler yazmış olur) ve `yayin`'ı `"acik"` yapar. Önce kuru koşu, sonra kurucu onayıyla `uygula`. |

## Yayın tarihi ve günlük takvim (göç 8290, v0.22.1)

- `ortak.oyunlar.ayarlar.yayin_tarihi` ('YYYY-AA-GG') yayın günü belli olunca yazılır, tarih kayarsa değiştirilir. `acilis().bayraklar.yayin_tarihi` herkese döner (yoksa belli değil).
- **Günlük takvim yayın tarihinden başlar.** Tarih kesinleşince (ya da değişince) oyun günlük içerik takvimini `yayin_tarihi`'nden başlatıp yeniden yükler (`<oyun>_gunluk_yukle`). Yükleme kuralı yalnız açılmamış gelecek günleri değiştirir. Böylece içeriğin 1. günü yayın günü olur ve önizleme döneminde boşa harcanmaz.
- **Örnekler kalır.** Yayından önceki günler (önizleme günleri) silinmez. Kurucu önizlemede bunları günlük ve arşiv olarak oynar, bakar. Yayın tarihi belli olmadan da günlük her gün gelir (içerik şimdiki takvimle sürer).
- **Oyun istemcisi:** "Gün N" numarası, arşivin ilk günü ve etkinlik ya da sezon takvimi `yayin_tarihi`'nden hesaplanır. Yayından sonra yayın öncesi günler halka açık arşivde gösterilmez; testçide gösterilebilir. Tarih yoksa önizleme takvimi (içeriğin kendi başlangıcı) kullanılır.
- **Etkinlik ve sezon** takvimi olan oyun (Halka, Koz, Ezber vb.) ilk etkinliği yayın tarihinden sonraki ilk uygun güne bağlar. Önizlemede etkinlik testçiye şimdiki takvimle açık kalır.
- **Lig:** ilk hafta yayın gününü içeren ISO haftası. Önizleme dönemindeki lig verisi yayın günü temizliğinde silinir.

## Oyunun yapacakları

1. **Vitrin.** İçerikte hangi seviyelerin ücretsiz olduğunu işaretle. Bu kısım her zorluk sınıfından ve her moddan ya da bulmaca türünden örnek içermeli; oyuncu oyunun nasıl büyüdüğünü ve çeşitliliğini görebilmeli. Boyutu oyuna göre önerilir, **kurucu oyun oyun onaylar** (oyun oturumunda seçenekli sor).
2. **Kilitli kısım.** Vitrin dışındaki seviyeler kilitli görünür. Önizlemede metin "Tam sürümde açılacak" olur; yayından sonra satın alma ekranı gelir. Testçide (`bayraklar.testci`) bütün seviyeler açıktır.
3. **Gizli kısımlar.** `bayraklar.kapali` içindeki özelliğin sekmesi, düğmesi, bildirimi ve onu anan metin gösterilmez. Bu, "kısa süre kapalı" uyarısı değildir; önizlemede özellik hiç yokmuş gibi davranılır. `onizleme` true ve `testci` true ise küçük bir "Önizleme" işareti gösterilebilir.
4. **Sunucu.** `dogrula-<oyun>` günlük, lig, etkinlik ve düello işlemlerinde `if (!(await c.ozellikAcik("gunluk"))) return c.hata(403, "kapali");` sorar. `ayarlar.bayraklar.kapali`'yı doğrudan okuyan eski kod bu yardımcıya geçer (aynı işlevi sorar).
5. **Hazır olunca** oyun-ortak oturumuna yaz: "önizlemeye alınabilir". `yayin` ancak o zaman `"onizleme"` yapılır; böylece istemci hazır olmadan özellik kaybolmaz.
6. **Takvim kaydırma:** günlük üretici ya da yükleyici bir başlangıç tarihi alabilmeli (ör. `--baslangic <yayin_tarihi>`). Komut oyunun belgesinde yazılı olsun; yayın tarihi gelince oyun-ortak oturumu ya da oyun oturumu çalıştırır.
7. **Yayın günü adımları** oyunun belgesine yazılır: `yayin-temizligi.ts`, oyuna özgü tablolar (varsa), noindex'in kaldırılması (`yayin.json` içinde `dizinlenebilir`), mağaza.

## İstisna: Hop Koala

Hop Koala'da (çocuk oyunu; günlük, lig ve sıralama yok) önizlemede de bütün içerik açık kalır. Vitrin ve kilit, mağazalara yüklenince kurulur (kurucu, 22 Kasım).

## Sınırlar

- Okuma RPC'leri (`siralama`, `lig_durumu`) önizlemede ayrıca kapatılmadı. İstemci göstermez; tabloya yalnız testçi yazabildiği için içinde yalnız testçi satırı olur. Yayın günü temizliği bunları siler.
- Test listesinden çıkarmak ya da eklemek oyun-ortak oturumunun işidir (kurucu onayıyla).
