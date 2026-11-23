# Yayın öncesi önizleme (kurucu kararı, 22 Kasım 2026)

Yayın tarihi kesinleşmemiş her oyun canlıda **önizleme** kipindedir. Bu, bütün oyunlar için geçerlidir (Halka, Beat Greedy ve Sticky Ten dahil). Bu kipte halka açık sitede yalnız seviyelerin ücretsiz kısmı (vitrin) açıktır; günlük, lig, etkinlik, sıralama ve düello gizlidir. Kurucunun hesabı test listesindedir ve canlı sitede her şeyi görüp oynar.

## Nasıl çalışır (göç 8280, paket v0.22.0)

| Parça | Ne yapar |
|---|---|
| `ortak.oyunlar.ayarlar.yayin` | `"onizleme"` ya da `"acik"`; alan yoksa `"acik"` sayılır. Oyunun oturumu hazır olunca oyun-ortak oturumu `"onizleme"` yapar. Yayın günü `"acik"` olur. |
| `ortak.testciler` | Önizlemede her şeyi gören hesaplar. Yalnız servis rolü okur. Liste oyun-ortak oturumunda tutulur (şimdilik yalnız kurucu). |
| `hesap.acilis().bayraklar` | Testçi olmayana `onizleme: true` döner; `kapali` listesine `gunluk`, `lig`, `etkinlik`, `siralama`, `duello` eklenir. Testçiye `onizleme: true, testci: true, lig_acik: true` döner; elle kapatılanlar dışında her şey açık. Yayından sonra da testçiye `testci: true` döner (göç 8300): bütün seviyeler her zaman açık. |
| `hesap.oyunBayraklari()` (göç 8310) | Oturum gerekmez. Testçi olmayan birinin göreceği bayraklar. Oturumu olmayan misafir (ilk açılış) önizleme kilidini ve gizlemeyi buradan uygular; oturum açılınca `acilis().bayraklar` geçerlidir (testçi bilgisi orada). |
| `c.ozellikAcik(ad)` (ortak-sunucu) | `dogrula-<oyun>` aynı kuralı sunucuda sorar: kapalıysa `c.hata(403, "kapali")`. |
| `scripts/yayin-temizligi.ts` | Yayın günü yayından önceki ortak skor, deneme, kurulum ve lig satırlarını siler (yalnız testçiler yazmış olur) ve `yayin`'ı `"acik"` yapar. Önce kuru koşu, sonra kurucu onayıyla `uygula`. |

## Yayın tarihi ve günlük takvim (göç 8290, v0.22.1)

- `ortak.oyunlar.ayarlar.yayin_tarihi` ('YYYY-AA-GG') yayın günü belli olunca yazılır, tarih kayarsa değiştirilir. `acilis().bayraklar.yayin_tarihi` herkese döner (yoksa belli değil).
- **Günlük takvim yayın tarihinden başlar.** Tarih kesinleşince (ya da değişince) oyun günlük içerik takvimini `yayin_tarihi`'nden başlatıp yeniden yükler (`<oyun>_gunluk_yukle`). Yükleme kuralı yalnız açılmamış gelecek günleri değiştirir. Böylece içeriğin 1. günü yayın günü olur ve önizleme döneminde boşa harcanmaz.
- **Hiçbir içerik boşa gitmez (kurucu, 22 Kasım).** Yayın gecikince içerik tarihlere yeniden dağıtılır, baştan üretilmez:
  - **Günlük:** yayın günü içeriğin başından (ya da oyunun seçtiği bir yerden) başlar; bütün içerik yayından sonraya dağıtılır. Önizlemede ya da önizlemeden önce birkaç günün görülmüş olması sorun değildir (kurucu, 22 Kasım): o içerik yeniden kullanılabilir, atlanabilir ya da yeniden üretilebilir; oyun en basit yolu seçer. Tek kesin kural içeriğin boşa gitmemesidir.
  - **Genel etkinlik:** sırası korunur, bütün dizi yayından sonraki ilk uygun güne kayar.
  - **Özel güne bağlı etkinlik** (yılbaşı, bayram, özel hafta vb.): tarihi yayından önce geçmişse sonraki yılın aynı gününe bırakılır; başka bir tarihe kaydırılmaz.
  - **Turnuva ve sezon:** ilki yayından sonra başlar; içerik ve sıra korunur.
  - **Lig:** zaten haftalık; ilk hafta yayın gününü içeren haftadır.
  - Oyunun takvim aracı bunları uygular (`--baslangic <yayin_tarihi>`, gerekirse `--ilk-icerik`) ve kuru koşuda hangi içeriğin hangi güne gittiğini listeler.
- **Örnekler kalır.** Yayından önceki günler (önizleme günleri) silinmez. Kurucu önizlemede bunları günlük ve arşiv olarak oynar, bakar. Yayın tarihi belli olmadan da günlük her gün gelir (içerik şimdiki takvimle sürer).
- **Oyun istemcisi:** "Gün N" numarası, arşivin ilk günü ve etkinlik ya da sezon takvimi `yayin_tarihi`'nden hesaplanır. Yayından sonra yayın öncesi günler halka açık arşivde gösterilmez; testçide gösterilebilir. Tarih yoksa önizleme takvimi (içeriğin kendi başlangıcı) kullanılır.
- **Etkinlik ve sezon** takvimi olan oyun (Halka, Koz, Ezber vb.) ilk etkinliği yayın tarihinden sonraki ilk uygun güne bağlar. Önizlemede etkinlik testçiye şimdiki takvimle açık kalır.
- **Lig:** ilk hafta yayın gününü içeren ISO haftası. Önizleme dönemindeki lig verisi yayın günü temizliğinde silinir.

## Oyunun yapacakları

1. **Vitrin = ücretsiz katman.** Önizlemede herkese açık olan kısım yayından sonra da ücretsiz kalır; satın alma geri kalanı açar. Günlük, lig, etkinlik ve turnuva da ücretsiz katmanın parçasıdır (giriş ister, A17): önizlemede gizli olmaları yalnız yayını beklemeleridir, ücretli değildirler. İçerikte hangi seviyelerin ücretsiz olduğunu işaretle. Bu kısım her zorluk sınıfından ve her moddan ya da bulmaca türünden örnek içermeli; oyuncu oyunun nasıl büyüdüğünü ve çeşitliliğini görebilmeli. Boyutu oyuna göre önerilir, **kurucu oyun oyun onaylar** (oyun oturumunda seçenekli sor).
2. **Kilitli kısım.** Vitrin dışındaki seviyeler kilitli görünür. Önizlemede metin "Tam sürümde açılacak" olur; yayından sonra satın alma ekranı gelir. Testçide (`bayraklar.testci`) bütün seviyeler açıktır.
3. **Gizli kısımlar.** `bayraklar.kapali` içindeki özelliğin sekmesi, düğmesi, bildirimi ve onu anan metin gösterilmez. Bu, "kısa süre kapalı" uyarısı değildir; önizlemede özellik hiç yokmuş gibi davranılır. `onizleme` true ve `testci` true ise küçük bir "Önizleme" işareti gösterilebilir.
4. **Sunucu.** `dogrula-<oyun>` günlük, lig, etkinlik ve düello işlemlerinde `if (!(await c.ozellikAcik("gunluk"))) return c.hata(403, "kapali");` sorar. `ayarlar.bayraklar.kapali`'yı doğrudan okuyan eski kod bu yardımcıya geçer (aynı işlevi sorar).
5. **Hazır olunca** oyun-ortak oturumuna yaz: "önizlemeye alınabilir". `yayin` ancak o zaman `"onizleme"` yapılır; böylece istemci hazır olmadan özellik kaybolmaz.
6. **Takvim kaydırma:** günlük üretici ya da yükleyici bir başlangıç tarihi alabilmeli (ör. `--baslangic <yayin_tarihi>`). Komut oyunun belgesinde yazılı olsun; yayın tarihi gelince oyun-ortak oturumu ya da oyun oturumu çalıştırır.
7. **Yayın günü adımları** oyunun belgesine yazılır: `yayin-temizligi.ts`, oyuna özgü tablolar (varsa), noindex'in kaldırılması (`yayin.json` içinde `dizinlenebilir`), mağaza. **Yayın öncesi kurucuya hatırlatılır:** gizlilik metinlerinde veri sorumlusu şimdilik "ASYWorks" (kurucu 23 Kasım); ASYWorks tüzel kişi değilse KVKK için satır yayından önce kurucuyla yeniden kararlaştırılır.
8. **Ücretli seviyeler pakette durmaz** (ortak çerçeve §5, satın alma açılmadan önce): pakette yalnız vitrin kalır; vitrin dışı seviyeler `korumali` kovasından `odeme.korumaliIndir` ile hak doğrulanınca iner (Ense, Ezber böyle). Testçi de korumalı yoldan alır. Kova yüklemesi oyun-ortak oturumunda. Önizlemede kilit yalnız istemcidedir; satın alma kapalı olduğu için bu geçici olarak kabul edilir.

## Testçi örnekleri (kurucu, 22 Kasım)

Testçi hesabında seviyeler dışında oyunda bulunan her oyun tipinden en az bir örnek olur; kurucu yayından önce hepsini dener:

| Tip | Testçide |
|---|---|
| Günlük | Her gün gerçek günlük; önizleme günleri arşivde |
| Etkinlik | Takvimden bağımsız, her zaman açık bir **örnek etkinlik** (gerçek içerik, gerçek `dogrula` yolu) |
| Turnuva | Varsa her zaman açık bir **örnek turnuva** |
| Lig | **Örnek lig görünümü**: testçinin kendi satırı ve dolgu satırları; kademe, çıkış ve iniş bantları görünür. Gerçek lig mantığı ortak testlerle sınanır, örnek lig sunucuya yazmaz |
| Düello ve benzeri | Varsa bir **örnek düello** |

- Örnekler yalnız `bayraklar.testci` iken görünür ve **yayında kullanılacak ekranlarda** açılır: örnek etkinlik etkinlik kartında, örnek lig lig ekranında, günlük günlük sekmesinde. Testçiye ayrı bir "Örnekler" ekranı ya da yeni arayüz yapılmaz; amaç yayın ekranlarını denemektir (kurucu, 23 Kasım). Sunucuda örnek isteği `await c.testciMi()` ile korunur; testçi olmayana 403.
- Örnek skorları gerçek sıralamaya yazılmaz ya da ayrı bir dönem kimliği taşır (ör. `ornek-…`); yayın günü temizliği bunları da siler.
- Yeni bir oyun tipi eklendiğinde örneği de eklenir.

## Ek kurallar (kurucu, 23 Kasım)

1. **Önizlemede ne kapalı, ne açık.** Sıralamaya giren her şey kapalıdır: günlük, etkinlik, turnuva, lig, sıralama, düello (göç 8360 turnuvayı listeye ekledi). Oyunu öğreten kısımlar açık kalabilir: öğretici, alıştırma, ilk bölümler, sıralamaya yazmayan deneme oyunları.
2. **Vitrinde zorluk sırası.** Önizlemede oyuncu bir zorluk sınıfının vitrindeki (ücretsiz) seviyelerini bitirmeden sonraki sınıf açılmaz. Sonraki sınıfın ne zaman açılacağını o sınıfın vitrindeki seviye sayısı belirler; ör. sınıf başına 5 ücretsiz seviye varsa 5'i bitince sonraki sınıfın ücretsiz seviyeleri açılır. Oyunun kendi açılma kuralı daha sıkıysa o geçerli.
3. **Testçi her şeyi her an açar.** Testçide vitrin sırası uygulanmaz: bütün ücretsiz seviyeler (ve ücretli seviyeler) her an açılabilir. Günlük, etkinlik, turnuva ve lig örnekleri de her an açıktır (yukarıdaki tablo).
4. **Yeni arayüz yok.** Testçi yayında kullanılacak ekranları kullanır; ayrı ekran, menü ya da düğme eklenmez. Kilit ve sıra yalnız açılıp kapanma olarak ayrışır.
5. **Kademeli açılış (ilk yayın).** Önizleme yapısı ilk yayında da kullanılabilir: yayın `acik` olunca `ayarlar.bayraklar.kapali` listesinde kalan özellikler (ör. etkinlik, lig) oyuncuya kapalı kalır; oyuncu sayısı arttıkça kurucu kararıyla listeden çıkarılır, oyunun yeni sürüm yayınlaması gerekmez. Testçi listeye takılmaz (göç 8360). Bunun için oyun her özelliği ayrı ayrı `bayraklar.kapali`'ya bağlar (istemci ve sunucu), hepsini tek "onizleme" bayrağına bağlamaz.
6. **Kapalı özellik her zaman hiç yokmuş gibi** (kurucu, 23 Kasım): önizlemede de yayından sonra da `kapali`'daki özelliğin sekmesi, düğmesi ve metni görünmez; adresi açılırsa seviyelere dönülür; ona bağlı alt özellik de kapanır (ör. günlük kapalıysa arşivi). "Kısa süre kapalı" kartı kullanılmaz. Geçici arızada oyuncuya bilgi `bayraklar.duyuru` metniyle verilir. `onizleme` bayrağı yalnız satış kilidini ("Tam sürümde açılacak") ve küçük "Önizleme" işaretini yönetir, özellik gizlemeyi değil.

## İstisna: Hop Koala

Hop Koala'da (çocuk oyunu; günlük, lig ve sıralama yok) önizlemede de bütün içerik açık kalır. Vitrin ve kilit, mağazalara yüklenince kurulur (kurucu, 22 Kasım).

## Sınırlar

- Okuma RPC'leri (`siralama`, `lig_durumu`) önizlemede ayrıca kapatılmadı. İstemci göstermez; tabloya yalnız testçi yazabildiği için içinde yalnız testçi satırı olur. Yayın günü temizliği bunları siler.
- Test listesinden çıkarmak ya da eklemek oyun-ortak oturumunun işidir (kurucu onayıyla).
