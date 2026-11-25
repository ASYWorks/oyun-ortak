# Değişiklik günlüğü

Her sürümde "Oyunlar ne yapmalı" bölümü vardır. Sürümleme semver; `0.x`'te küçük sürüm kırıcı olabilir.

## v0.23.0 (25 Kasım 2026)

Codex incelemesi (D02, D03, D09, MD-24) ve Opus 5.5 uygulaması.
- `kayitDeposu().birlestir(yerel, fn, { kim })` hesap doğrulamalı işlevlerle çalışır (göç 8440: `kayit_oku_hesapli`, `kayit_yaz_hesapli`). Oturum iki istek arasında başka hesaba geçerse `hesap_degisti` fırlatır; başka hesabın kaydı okunmaz ve yazılmaz. Göç uygulanmamışsa `kayit_hesapli_yok` fırlatır; eski işlevlere düşmez.
- Skor kuyruğu (D02): her kayıt gönderen hesaba bağlanır ve yalnız o hesabın jetonuyla gider. Misafir kaydı kalıcı hesaba gitmez.
- Web devri (D03): devir kaydı geçici hatada silinmez, aynı hesapta yeniden denenir. 30 dakika sonra düşer. Aynı anda gelen çağrılar tek devri paylaşır.
- Ölçüm (D09): parti 60 KB'ı aşmaz (`keepalive` sınırı). Sığmayan olay kuyruktan düşer. İzin kapatılıp açılınca eski yanıt yeni kuyruğa dokunmaz.
- Yayın betiği: paket SHA-256, tam commit ve dağıtım kimliği günlüğe yazılır; kilitli npm/pnpm kurulumu. Yedek betiği: hazırlık dizini, doğrulama, atomik yayımlama ve yalnız geçerli yedeklerin rotasyonu. Günlük görev Docker kapalıysa açar.
- **Oyunlar ne yapmalı:** `birlestir` çağrısında `kim` veriyorsanız (MD-24) bu sürüme geçin. Davranış değişikliği yoktur; yalnız sunucu da hesabı doğrular.

## v0.22.3 (22 Kasım 2026)

- ortak-sunucu `c.testciMi()`: testçiye özel örnek içerik için.
- **Oyunlar ne yapmalı:** testçide her oyun tipinden en az bir örnek (günlük, örnek etkinlik, örnek turnuva, örnek lig görünümü, örnek düello); `docs/ONIZLEME.md` "Testçi örnekleri".

## v0.22.2 (22 Kasım 2026)

- `hesap.oyunBayraklari()` (göç 8310): oturumsuz ziyaretçi için oyunun halka açık bayrakları (önizleme, kapali, yayin_tarihi). Testçi bilgisi yine `acilis()`'te.
- Göç 8300: testçiye yayından sonra da `testci: true`.
- **Oyunlar ne yapmalı:** oturum yokken açılışta `oyunBayraklari()`, oturum varken `acilis().bayraklar`; bütün seviyeleri yalnız `testci`'ye bağla.

## v0.22.1 (22 Kasım 2026)

- Yayın tarihi (göç 8290): `ayarlar.yayin_tarihi`; `Acilis.bayraklar.yayin_tarihi` herkese döner.
- **Oyunlar ne yapmalı:** "Gün N", arşivin başı ve etkinlik takvimi `yayin_tarihi`'nden hesaplansın; günlük yükleyici başlangıç tarihi alsın (`docs/ONIZLEME.md`).

## v0.22.0 (22 Kasım 2026)

- Yayın öncesi önizleme (göç 8280, `docs/ONIZLEME.md`):
  - `ortak.oyunlar.ayarlar.yayin` (`onizleme` | `acik`) ve `ortak.testciler`.
  - `Acilis.bayraklar`: `onizleme` ve `testci`; testçi değilse `kapali` içine gunluk, lig, etkinlik, siralama, duello eklenir.
  - ortak-sunucu `c.ozellikAcik(ad)`.
  - `scripts/yayin-temizligi.ts` (yayın günü).
- **Oyunlar ne yapmalı:** vitrin seviyelerini işaretle (boyut kurucu onayıyla); `kapali` özelliği hiç göstermeden gizle; testçide bütün seviyeleri aç; `dogrula` içinde `c.ozellikAcik` sor; hazır olunca oyun-ortak oturumuna "önizlemeye alınabilir" yaz.

## v0.21.2 (20 Kasım 2026)

- `Acilis.bayraklar`: sunucu kontrollü bayraklar (`ortak.oyunlar.ayarlar.bayraklar`). Öneri: `kapali` (özellik listesi), `asgari_surum` ve `duyuru`. Göç 6800; `halka_gonderim_verisi` de döndürür (göç 7000).
- İşletim (göç 6800/6900):
  - `ortak.isletim_durumu()` (servis rolü ve salt okunur rol).
  - Yönetim kaydı.
  - Açılmış bulmaca koruması.
  - Haftalık ödül işleri 03:05 ve 03:15 İstanbul.
- Betikler: `scripts/yedek.sh` (yedek), `scripts/saglik.ts` (sağlık). Belge: `docs/ISLETIM.md`.

## v0.21.1 (19 Kasım 2026)

- `hesap.idTokenIleGir`: captcha jetonu artık istenmiyor.
  - Supabase kimlik jetonuyla girişte captcha denetlemiyor; test projesinde captcha açıkken sınandı, jetonsuz istek doğrudan kimlik jetonu doğrulamasına gidiyor.
  - Jeton beklemek, Turnstile hazır değilken ilk Google/Apple girişini düşürüyordu (kurucunun telefon denemesi).
  - Güvenliği Google ve Apple'ın imzalı jetonu sağlar. Anonim giriş ve e-posta kodu captcha istemeye devam eder.

### Oyunlar ne yapmalı

- v0.21.1'e geçin. Beat Greedy ve Sticky (v0.17.0) da geçmeli; yoksa captcha açıkken ilk Google girişi aynı şekilde düşebilir.

## v0.21.0 (19 Kasım 2026)

İstek sayısı ve ölçek (kurucu 19 Kasım: "verimsiz kısımları düzeltelim", "aynı mantığı başka yerlere de uygula").

- **`hesap.acilis()`** (göç 20261120006500): açılışta tek istek. `ben` ile aynı işi yapar ve şunları döndürür:
  - Sürüm damgaları: `profil`, `oduller`, `haklar`, `kayit`.
  - Oyunda lig varsa lig durumu (`lig`).

  Cihazdaki kopyanın damgası aynıysa o bilgi istenmez. Profil damgası lig ve turnuva sırasını kapsamaz, gün değişince değişir.
- **`bulutKaydi().birlestir`:** son okunan ya da yazılan kayıt bu hesap için bellekte tutulur, yazma okumadan denenir. Sürüm tutmazsa (başka cihaz yazdı) okunup yeniden birleştirilir; veri kaybı yok. `acilis()` bulut damgası farklıysa bellek düşer.
- **`ben`:** `son_gorulme` saatte en çok bir kez yazılır.
- **Sunucu:**
  - Edge kullanıcı ve oyun hız sınırı tek istek (`istek_siniri`).
  - `skor_yaz` yeni ve tekrar yanıtında sırayı döndürür (`c.sira()` ayrı istek atmaz).
  - `halka_gonderim_verisi` (göç 6400).
- **Sıralama indeksli (göç 6100/6200):** 10.000 skorda oyuncu sırası 26'dan 6 ms'ye iner. Sonuçlar eskisiyle birebir aynı.
- **Güvenlik:** `run_id` kullanıcıya bağlı (5800). Sıralama, Sticky sıralaması ve profil hız sınırı yalnız `cf-connecting-ip` ile (5800–6000). Sticky dönem başlangıcı yalnız servis rolünden (6000).
- Nabız 30 sn için ipucu duraklatma eşiği 45 sn (6300).
- `cron.job_run_details` 7 günden eskisi her gece silinir.

### Oyunlar ne yapmalı

- Açılışta `ben`, `odullerim`, `lig_durumu`, `kayit_oku` yerine `hesap.acilis()` çağırın. Damgaları hesap kimliğine göre cihazda saklayın; yalnız damgası değişeni isteyin.
- Önbelleği hesaba göre ayırın: çıkışta ya da hesap değişince başka hesabın verisi görünmesin.
- `dogrula-<oyun>`: `skor_yaz` yanıtında `sira` var. Yeni durum `run_id` (başkasının runId'si) skor yazmaz; yeni runId ile bir kez yeniden gönderin.

## v0.20.0 (19 Kasım 2026)

- **Güvenlik (göç 20261120005600):**
  - Süre: 90 sn'ye kadar nabız aralığı tam sayılır. Durdurulmuş aralık ve daha uzun boşluk `durak_ms`'e yazılır.
  - Duraklatma etkin süreyi ve 2 dakikayı aşarsa skor `nabiz_boslugu` bayrağı alır. Bayraklı skor tabloda kalır, sıra ödülüne ve lig puanına girmez.
  - `sunucu/sure.ts`: `aktifSureMs` artık tavansız; yeni `nabizBoslugu`. Beat Greedy'de aynı kural geçerli.
  - Halka'da anlam ve kilit ipucu ile bugünün ve turnuvanın kontrolü yalnız kalıcı hesaba açık.
  - Başkasının profilinde istemcinin yazdığı `rozet-…` ödülleri görünmez.
  - `kayit_yaz` dakikada 30. Beat Greedy ligleri doğrudan UPDATE ile değiştirilemez.
- **Lig:** o hafta günlük skoru olan oyuncu puanı 0 da olsa sıraya girer.
- **Yük (göç 20261120005700):**
  - Halka kontrolü nabız da sayar.
  - `nabizBaslat(...)` dönen işlevde `dokundu()` var: son aralıkta nabız sayan başka istek gittiyse döngü nabız göndermez.

### Oyunlar ne yapmalı

- Nabız sayan istekten (Halka: başarılı kontrol) sonra `dokundu()` çağırın. Çağırmayan oyunda davranış aynı kalır.
- `kayit_yaz` dakikada 30'u aşarsa `cok_istek` (54000) döner; sessizce bekleyip yeniden deneyin.
- `dogrula-<oyun>` deneme kaydından `durak_ms`'i okur ve `nabizBoslugu` true ise skora `nabiz_boslugu` bayrağı yazar.

## v0.19.1 (18 Kasım 2026)

- `Profil.gunluk` alanına üç sayı eklendi:
  - `simdiki_seri`: bugün ya da dün biten ardışık gün sayısı.
  - `hedef_sure`: süresi o günün hedefini aşmayan gün sayısı.
  - `hedef_hamle`: hamlesi o günün hedefini aşmayan gün sayısı.
  Hedef sayılarına yalnız puan sürümü 4 ve sonrasındaki günler girer.
- Sunucu: 90 günlük saklama işi skor ayrıntısını tamamen silmez. `puan_surumu`, `sure`, `hamle`, `hedef_sure` ve `hedef_hamle` kalır, sayılar zamanla düşmez. Göç 20261120005500.

### Oyunlar ne yapmalı

- Hedef sayılarını kullanacak oyunun `dogrula-<oyun>` fonksiyonu skor ayrıntısına `sure`, `hamle`, `hedef_sure`, `hedef_hamle` ve `puan_surumu` yazmalıdır. Halka 8350f32'den beri yazıyor.

## v0.19.0 (18 Kasım 2026)

- **Oyuncu profili** (Halka isteği):
  - `siralama.profil(id)` profili döndürür; girişsiz de çağrılabilir, dakikada 30 istek.
  - `siralama.profilAyari({ gizli?, desen? })` girişli oyuncunun kendi ayarıdır. Misafir kaydedemez (`misafir`), misafirin profili de dönmez.
  - Tablo satırları (`Satir.profil`) ve lig üyeleri rastgele profil kimliği taşır; kullanıcı kimliği dışarı çıkmaz.
  - Gizli profilde yalnız ad görünür.
- `LigDurumu.uyeler[].ikincil`: lig eşitliğinde kullanılan ham değer. Birimi oyuna aittir; Halka v4'te süre×1000+hamle.
- `Tablo.kapandi`: dönemin sıra ödülü yazıldıysa (kapanış işi çalıştıysa) true.
- Sunucu göçleri 20261120004800–20261120005400 test ve canlıda.

### Oyunlar ne yapmalı

- Profil göstermeyen oyun için bir şey gerekmez.
- Profil gösteren oyun gizlilik metnine şu cümleyi ekler: "Sıralamaya giren oyuncuların adı, ligi, rozetleri ve oyun istatistikleri diğer oyunculara görünür. Ayarlar'dan kapatılabilir."

## v0.18.1 (17 Kasım 2026)

- `olcum.hata` iletiden e-posta adreslerini, uzun jetonları ve adreslerin `?…`/`#…` kısmını ayıklar (OAuth dönüşü `#access_token` taşır). Yığın çerçevelerinde dosya adının sorgu kısmı atılır. İleti en çok 300 karakter.

### Oyunlar ne yapmalı

- Bir şey gerekmez; v0.18.0 kullanan sürüm v0.18.1'e geçer.

## v0.18.0 (17 Kasım 2026)

- Hata takibi (OL-4): `olcum.hata(e, ozellik?)` hatayı PostHog `$exception` biçiminde gönderir. PostHog "Error tracking" ekranında hatalar gruplanır. Yığın çerçevelere çözülür (Chrome, Firefox, Safari). Aynı ileti oturumda bir kez gider, oturumda en çok 20 hata gider. Ölçüm kapalıysa hiçbir hata gitmez. Elle yakalanan hatada `{ elle: true }` verilir.
- Source map PostHog'a yüklenmez, çünkü kişisel API anahtarı ister. Derleme `sourcemap: "hidden"` olur, haritalar yerelde sürüm sürüm saklanır, yığın gerektiğinde yerelde çözülür.

### Oyunlar ne yapmalı

- `window` `error` ve `unhandledrejection` dinleyicilerinde `olay("hata", …)` yerine ya da yanında `olcum.hata(e.error ?? e.reason, { sayfa })` çağrılır. `hata` olayı listede kalır, çalışan kod kırılmaz.
- Derlemede `build.sourcemap: "hidden"` kullanılır. `.map` dosyaları Pages'e yüklenmez; her sürümün haritaları depo dışında saklanır (Halka c537892 örnek).

## v0.17.0 (17 Kasım 2026)

- Bot koruması hazırlığı (OL-9, Cloudflare Turnstile; kurucu 17 Kasım): `hesapBaslat`, `siralamaBaslat` ve `odemeBaslat` ayarlarına `captcha?: () => Promise<string>`. Verilirse anonim giriş, e-posta kodu ve kimlik jetonuyla giriş isteğine `captchaToken` eklenir; her çağrıda yeni jeton istenir. Verilmezse davranış aynı.
- Sunucuda captcha henüz kapalı. Dört oyun sağlayıcıyı verip yayınlayınca önce test bulutunda, sonra canlıda açılacak. Açılınca sağlayıcısız sürüm e-posta koduyla ve misafir olarak giriş yapamaz; Google ve Apple yönlendirmeli giriş etkilenmez.

### Oyunlar ne yapmalı

- Bütün oyunlar: görünmez Turnstile ile jeton üreten bir işlev yazıp aynı işlevi `hesapBaslat`, `siralamaBaslat` ve (varsa) `odemeBaslat`'a `captcha` olarak verir. Site anahtarı açıktır, oyunun ayarında durabilir; gizli anahtar yalnız Supabase'te. Gizlilik metnine Cloudflare Turnstile satırı eklenir.
- Geçişi bitirip yayınlayınca oyun-ortak'a bildirir. Captcha ancak dördü de hazır olunca açılır.

## v0.16.3 (17 Kasım 2026)

- `odeme`: hak önbelleği hesaba bağlı (ÖG-1, O15). Önbellek sahibini (`k`) yazar; oturumdaki hesap başkasıysa önbellek okunmaz, A'nın paketi aynı cihazda B'ye açık görünmez. Oturum bilinmiyorsa (ağsız, süresi dolmuş) önbellek olduğu gibi kalır (ÖG-4). Sahipsiz eski önbellek ilk yenilemede sahiplenir.
- Sunucu: `ortak.sakli_ad` (SA-1, göç `20261120004500`).
- Ortak kural: oyunlardan öğrenilenler `_ortak/OGRENILENLER.md`'de toplanır; denetime O16 (bulut kaydı dayanıklılığı) ve O17 (ağ ve gecikme) eklendi.

### Oyunlar ne yapmalı

- Ödemeli oyun: paket güncellemesi yeter.
- Herkes: `_ortak/OGRENILENLER.md`'yi okuyup O16 ve O17'yi kendi denetiminde doldurur.

## v0.16.2 (17 Kasım 2026)

- `siralama`: `SiralamaAyari.sonuc` geri çağrısı her gönderim sonucu için çağrılır: `gonder`'in kendisi, onunla giden kuyruktaki öncekiler ve `bosalt` ile gidenler (GC-1). Süren bir boşaltmaya denk gelen `gonder` artık bir tur daha deneyip kendi sonucunu döndürür (önceden `bekliyor: true` dönüp sonraki boşaltmayı bekliyordu).
- `hesap.bulutKaydi().birlestir`: birleşim buluttakiyle aynıysa `kayit_yaz` çağrılmaz (GC-2). Anahtar sırası ve `undefined` alanlar fark sayılmaz (`ayniJson`).
- Sunucu: silinen hesabın ad kilidi (AD-1, göç `20261120004300`, `20261120004400`). Silmede kilit sürüyorsa ad saklanır, yeniden açınca geri gelir, kilit sürerken başkasına verilmez.

### Oyunlar ne yapmalı

- Halka: `gonder`'den önce `bosalt` çağırma geçici çözümü yerine `sonuc` geri çağrısı kullanılabilir.
- Beat Greedy: profil açılışında `ad_bekle` gelebilir (yapıldı, 93d89c0).

## v0.16.1 (16 Kasım 2026)

- `siralama` gönderim kuyruğu hesaba bağlı (O15, Halka'nın bulgusu): her öğe gönderen hesabın kimliğini taşır. Başka hesabın oturumu açıkken o öğe gönderilmez, kuyrukta bekler, sahibi dönünce gider. Kimliksiz eski öğeler eskisi gibi gider. Silinen hesabın öğeleri gitmez, kuyruk sınırı (50) içinde kalır.
- Halka: `halka_dogrula_bulmaca` ve `halka_dogrula_turnuva` `kilit_sirasi`'nı da döndürür (göç `20261120004200`, kilit hamlesi denetimi).

### Oyunlar ne yapmalı

- Kuyruğu paketten kullanan oyun: sürümü yükselt, başka değişiklik gerekmez.

## v0.16.0 (16 Kasım 2026)

- Hesaplar cihazda ayrı (O15, Halka Kelime'nin çözümünden): `kayit` paketine `sahipDenetle`, `hesapDegistir`, `sahipOku`. `<oyun>:sahip` cihazdaki ilerlemenin sahibi (misafirde "", kural öncesi kurulumda null). Hesap değişince verilen anahtarlar (ve `:yedek`, `:bozuk` eşleri) eski hesabın cihazdaki yedeğine (`<oyun>:hesap:<kimlik>`) taşınır, giren hesabın yedeği geri gelir. Misafirinki katılır (`birlestir`). Silmede `yedekle: false`. Yarıda kesilen geçiş yeniden çağrıda tamamlanır.
- Halka: anlam ipucu sunucuda 2 hakla sınırlı, günlük sıralamada eşitlik ikincil (göç `20261120004000`). Anlam ipucu oyuncunun çerçevesinde (göç `20261120004100`, `halka.cerceve`, `halka.dilim_oku`; `kilit_sec` davranışı aynı).

### Oyunlar ne yapmalı

- Girişi olan her oyun: O15'e uy. Açılışta ve her oturum değişiminde `sahipDenetle`, çıkışta ve silmede `hesapDegistir`. Önce açık oyunu kaydedip kapat ve eşitlemeyi durdur, sonra sayfayı yeniden aç. Çıkışta kayıtları düz silen kod (ör. "yerelTemizle") kalkar.
- Halka: kendi çözümü O15'e uyuyor. Pakete geçmek isteğe bağlı.

## v0.15.7 (16 Kasım 2026)

- Metin kuralı (kurucu): ayraç olarak orta nokta (·) yok, noktalı virgül gerçekten gerekmedikçe yok (ARAYUZ_KURALLARI §5, denetimde M1). `AD_METINLERI.{tr,en}.kural` noktalı virgülsüz. Site başlıkları ve yasal metinler buna göre.

## v0.15.6 (16 Kasım 2026)

- Güvenlik (durdur nabzı): teslimde `durdu` yok sayılır; durmuş denemede teslim de son aralığı en çok 15 sn sayar (hileli istemci durdurup teslim ederek son aralığı sıfırlayamaz). İlk nabız denemeyi durmuş açamaz. `aktifSureMs` `durdu`ya bakmaz. Göç `20261120003900`.

### Oyunlar ne yapmalı

- Halka: kural.ts'teki "durdu ise yalnız aktif_ms" dalını kaldır; süre her zaman `aktifSureMs(d, simdi) ?? duvar saati`.

## v0.15.5 (16 Kasım 2026)

- Düzeltme (duraklatma cezası): duraklatıp dönen oyuncunun ilk nabzı aradaki süreden en çok 15 sn ekliyordu. Artık durdur nabzı var: `ortak.nabiz(oyun, anahtar, p_durdur)` ve `sezgi.nabiz(deneme, p_durdur)`; durdur o ana kadarki süreyi sayar ve sayacı durdurur, devam süre eklemeden başlatır. `durdu` sütunu (ortak.denemeler, sezgi.attempts); durmuş denemede ipucu yok (Halka ve Beat Greedy); bitirmede süre aktif_ms. Göç `20261120003800`.
- `siralama`: `nabiz(anahtar, durdur?)`; `nabizBaslat`'ın durdurucusu ve sayfa gizlenmesi durdur nabzı gönderir.
- `sunucu`: `aktifSureMs` `durdu`yu bilir; `Deneme.durdu`.

### Oyunlar ne yapmalı

- Halka: paketi 0.15.5'e çek; dogrula-halka deneme okumasına `durdu` sütununu ekle (aktifSureMs'e gider).
- Beat Greedy: duraklatınca ve arka plana geçince `sezgi.nabiz(deneme, true)`; Devam et'te `p_durdur` vermeden nabız.

## v0.15.4 (16 Kasım 2026)

- Sunucu (Beat Greedy, SÜ-BG; ADIL_PUAN §6): `sezgi.attempts.aktif_ms`, `son_nabiz`; `sezgi.nabiz(p_attempt)` (yalnız kendi açık denemesi; ilk nabız sayacı başlatır, sonraki her nabız en çok 15 sn ekler). `finish_attempt_tx` nabız geldiyse aktif süreyi, gelmediyse duvar saatini yazar. `count_hint` duraklatılmış denemede `duraklatildi`. Göç `20261120003700`.

## v0.15.3 (16 Kasım 2026)

- Sunucu (Halka): duraklatılmış denemede ipucu yok. `halka.ipucu_ver` nabızlı denemede son nabız 15 sn'den eskiyse `duraklatildi` hatası verir, ipucu yazılmaz; nabızsız denemede davranış aynı (kurucu). Göç `20261120003600`.

## v0.15.2 (16 Kasım 2026)

- Duraklatılabilir sıralama süresi (Halka isteği; kurucu: "Duraklatmaya izin verilsin"): `ortak.denemeler.aktif_ms`, `son_nabiz`; `ortak.nabiz(oyun, anahtar)` (ilk nabız denemeyi açar; her nabız önceki nabızdan bu yana geçen süreyi, en çok 15 sn, ekler; bitmiş denemede durur). Göç `20261120003500`.
- `siralama`: `nabiz(anahtar)`, `nabizBaslat(anahtar, aralikMs = 10000)` (sayfa gizliyken göndermez; dönen işlev döngüyü durdurur).
- `sunucu`: `aktifSureMs(deneme, simdi)` (nabız yoksa null, oyun duvar saatini yedek kullanır); `Deneme`'ye `aktif_ms`, `son_nabiz`.

### Oyunlar ne yapmalı

- Halka: Başla/Devam'da `nabizBaslat(denemeAnahtari)`, duraklatınca ve bitince durdur; dogrula-halka süreyi `aktifSureMs(deneme, simdi) ?? duvar saati` ile alır. Duraklayınca tahta gizlenir.

## v0.15.1 (16 Kasım 2026)

- Sunucu (bildirim): `ortak.bildirim_anahtarlari.konular` (oyuncunun açtığı konular, ör. `takip`, `bekleyen`); `bildirim_anahtari_yaz(..., p_konular text[] default null)` (null var olanı korur). `ortak.bildirim_hakki_al(oyun, konu, kullanicilar uuid[])`: konu başına alıcı başına günde bir hak, sunucu yeniden başlasa da (yalnız servis rolü). Göç `20261120003300`.
- Kural: oyuncunun kendi açtığı fırsat bildirimi (Sticky "Biri masada bekliyor") haftalık ek sınırına girmez; günde en çok 1, 10:00–23:00, varsayılan kapalı, adsız (kurucu).

### Oyunlar ne yapmalı

- Sticky Ten: tercih açılınca anahtar `p_konular`'a `bekleyen` eklenerek yazılır; sunucu alıcıları `konular @> '{bekleyen}'` ile seçer, göndermeden önce `bildirim_hakki_al` ile günlük hakkı düşer.

## v0.15.0 (16 Kasım 2026)

- **Kırıcı (kural ve Beat Greedy sunucusu):** puan ölçeği 0–100 tamsayı (ADIL_PUAN §1; önceki 0–5 × 20, yuvarlanmış; kurucu, hemen geçerli). `sezgi.record_level` seviye puanını 0–100 tamsayı ister (ondalıklı ya da aralık dışı `bad_puan`); `board_levels.master3` = puanı 100 olan seviye sayısı. Göç `20261120003400`.

### Oyunlar ne yapmalı

- Halka ve Beat Greedy: puan işlevi 0–100 tamsayı döndürür (0–5 × 20, yuvarla, 0–100'e kırp); hedeften hızlı çözenlerin farkı `ikincil`'e (süre) geçer. Döküm kalemleri, tablolar, lig ve rozet eşikleri tamsayı ve 20 katı. Beat Greedy: göç canlıya submit_level/submit_attempt yeni motorla birlikte girer (eski submit_level 0–5 ondalık gönderir, reddedilir).

## v0.14.6 (16 Kasım 2026)

- Sunucu (Beat Greedy, PU-7 g): `sezgi.my_daily_stats()` puan v1 alanları: `avg_puan`, `recent_puan` (14 gün), `games[oyun].avg_puan`; eski alanlar aynen. Göç `20261120003200`.

## v0.14.5 (16 Kasım 2026)

- Sunucu (Sticky Ten, ST-10 düzeltmesi; güvenlik incelemesi): "bu oyundan sil" puanlı oyun kaydını silmez, yalnız oyuncunun satırını çıkarır; aynı oyun kimliği yeniden gelirse öbür oyunculara ikinci kez yazılmaz. Göç `20261120003100`.

## v0.14.4 (16 Kasım 2026)

- Sunucu (Sticky Ten, ST-10): `sticky.puanli_sonuc_yaz(p_oyun uuid, p_gun text, p_oyuncular jsonb [{kullanici, delta}], p_ikililer text[])`: puanlı oyunun rating parçaları tek işlemde, oyun kimliğiyle bir kez; tekrar çağrı ilk sonucu `tekrar: true` ile döner. Yalnız servis rolü. `rating_log.oyun` sütunu.
- Sunucu (Sticky Ten, ST-11): `sticky.siralama` ve `haftalik_odul` eşitlikte değer, oyun sayısı, sonra ad.
- Göç `20261120003000`.

### Oyunlar ne yapmalı

- Sticky Ten: puanlı oyun sonunda `rating_uygula` döngüsü ve ayrı `rated_pairs` yazımı yerine tek `puanli_sonuc_yaz` çağrısı; oyun kimliği masa devrinde taşınır.

## v0.14.3 (16 Kasım 2026)

- Sunucu (adil puan, PU-8): `ortak.puan_ayar` (oyun × sürüm × geçerli Pazartesi × ayar); süren ve kapanmış hafta değişmez. Okuma `ortak.puan_ayari(oyun, gün)`, yalnız servis rolü.
- Sunucu (Beat Greedy, PU-7 b, e, f): tablolar tarih kapısıyla yeni puana geçer (kapı: ilk ayar sürümünün Pazartesi'si); eski sütunlar aynen, sona `puan` ve `ikincil`. Hafta en iyi 5 gün. Seviye puanı `level_verified.puan`, `record_level(..., p_puan)`. `sezgi.kalibrasyon(bas, bit)`. Göç `20261120002900`.

### Oyunlar ne yapmalı

- Beat Greedy: `submit_attempt` `attempts.puan`, `puan_surumu`, `ayrinti.lt` (ve sure_ms, hedef_ms, kademe, ipucu) yazar, hedef süreyi `ortak.puan_ayari('sezgi', gün)`'den okur; `submit_level` `record_level`'a `p_puan` verir. İlk ayar satırı (geçiş Pazartesi'si) eklenince tablolar o günden yeni puanla sıralanır.

## v0.14.2 (16 Kasım 2026)

- Sunucu (adil puan): `ortak.kalibrasyon(oyun, bas, bit)`: dönem başına süre dağılımı, ipucu oranı ve türleri (yalnız servis rolü; PU-3). Göç `20261120002700`.
- Sunucu (Beat Greedy): `sezgi.attempts`'e `puan`, `puan_surumu`, `ayrinti`; Yarış ipucu hakkı 3, dördüncüsünde `ipucu_hakki_bitti`; lig eşitliği `ikincil`. Göç `20261120002800`.

### Oyunlar ne yapmalı

- Beat Greedy: `race_hint`, `count_hint`'in `ipucu_hakki_bitti` hatasını oyuncuya metinle döndürür (500 değil).
- Halka: ilk kalibrasyonu 23 Kasım'dan sonra `ortak.kalibrasyon` ile servis rolüyle oku.

## v0.14.1 (15 Kasım 2026)

- Sunucu: Beat Greedy'nin eski ad kısıtı (`sezgi.profiles.username_format`, `^[A-Za-z0-9_]{3,20}$`) kalktı; Türkçe harfli ve noktalı adlar artık reddedilmiyor. Ad biçimini yalnız ortak kural denetler. Göç `20261120002500`. Oyunların yapacağı bir şey yok.

## v0.14.0 (15 Kasım 2026)

- **Kırıcı (sunucu):** ortak kullanıcı adı kuralı, bütün oyunlarda aynı: 3–20 karakter; harf (Türkçe harfler dahil), rakam, `_` ve `.`; boşluk yok; `_` ve `.` başta, sonda ve yan yana olamaz; en az bir harf. Tire artık yok; Halka'da 2 karakterlik ad artık yok. Oyun ayarı bu sınırları yalnız daraltabilir. Göç `20261120002400`. Canlıdaki seçilmiş adların hepsi kurala uyuyor.
- `hesap`: `AD_KURALI`, `adBicimiUygun(ad)` (sunucuyla aynı kural, anlık denetim için) ve `AD_METINLERI.{tr,en}.kural`.

### Oyunlar ne yapmalı

- Ad adımında kural metnini göster (`AD_METINLERI[dil].kural`), yazarken `adBicimiUygun` ile denetle; uymayan adla Kaydet düğmesi kapalı kalsın. `bicim` dönüşünde de aynı metni göster.
- Ad alanında kendi sınırın varsa (`maxLength`, kendi düzenli ifaden) kaldır ya da 20'ye çek; boşluk ve tireye izin veren metinleri düzelt.

## v0.13.0 (15 Kasım 2026)

- **Kırıcı (sunucu):** sıralamaya girmek için seçilmiş ad şart. Adı otomatik olan (`#XXXXX`) hesabın `skor_yaz`/`gun_toplami_yaz` çağrısı skor yazmaz, `durum: "ad_gerekli"` döner. Göç `20261120002300`.

### Oyunlar ne yapmalı

- Girişten sonra `hesap.ben().ad_otomatik` ise "Sıralamada görünecek adın" adımını aç (`adDegistir`); ad seçilmeden günlük, lig ve etkinliğe sıralamalı giriş yok.
- Gönderim yanıtı `durum: "ad_gerekli"` ise ad seçtir ve aynı gönderimi yinele.

## v0.12.2 (15 Kasım 2026)

- `SIRALAMA_METINLERI.cihaz` açık dil kuralına göre yeniden yazıldı: "skor" yerine oyundan bağımsız "sonuç", tekrar eden "sıralamaya" çıktı, iki tam cümle.

## v0.12.1 (15 Kasım 2026)

- `geriBildirimGonder` kuyruğa girmez, hemen gönderir; ağ yoksa ya da PostHog reddederse `gonderilemedi` fırlatır (oyunun `navigator.onLine` kontrolüne gerek kalmaz). `olcum.hemenOlay()` eklendi.

## v0.12.0 (15 Kasım 2026)

- `olcum`: `acik()`, `ayarla(acik)` (oyuncunun ölçüm tercihi, varsayılan açık) ve `adsizOlay()` (cihaz kimliksiz tek olay).
- `geri-bildirim`: `geriBildirimGonder(olcum, tur, metin, { ekran })` kalıcı form; ölçüm kapalıyken adsız gider. Anket cevapları da ölçüm kapalıyken adsız gider.
- Sunucu: `sezgi.game_sign` 16 oyun (BG-11); Halka'nın eski ölçüm tabloları (`hk_opens`, `hk_plays`, `hk_errors`) ve görünümleri kaldırıldı (O1). Göçler `20261120002000`, `20261120002100`.

### Oyunlar ne yapmalı

- Ayarlara "Kullanım ölçümü" anahtarı koy (`olcum.ayarla`); gizlilik metni "takip yok" diyorsa ölçüm tercihini ona göre anlat.
- Kalıcı geri bildirim formu için `geriBildirimGonder` kullan.

## v0.11.1 (15 Kasım 2026)

- `GIRIS_RENKLERI`: her düğmeye `basili` (basılı durum zemini) (BG-9). Form genişliği tanımı: içerik genişliği en çok 400 px.
- asyworks.com/gizlilik ve /hesap-sil `?oyun=<kimlik>` (halka, sticky, sezgi) ile yalnız o oyunu anar (BG-10).

### Oyunlar ne yapmalı

- Oyun içinden asyworks.com yasal sayfalarına bağlantı veriyorsan `?oyun=<kimlik>` ekle (ör. `https://asyworks.com/gizlilik/?oyun=sezgi`).
- Basılı rengi elle yazma, `GIRIS_RENKLERI.<sağlayıcı>.<tema>.basili`'yi kullan.

## v0.11.0 (15 Kasım 2026)

- `siralama.ligGecmisi(n)`: oyuncunun kapanmış lig haftaları (kademe, sıra, sonuç, puan, grup büyüklüğü), en çok 26 (HK-13). Göç `20261120001900`.

### Oyunlar ne yapmalı

- Sıralama ekranında geçmiş lig haftalarını `ligGecmisi()` ile, bitmiş etkinlik sıralamasını `tablo("etkinlik", id)` ile göster.

## v0.10.1 (15 Kasım 2026)

- `etkinlik.yerelTemizle()`: çıkışta cihazdaki ödülleri siler (önce eşitlemeyi dener), aynı cihazda giren başka hesaba geçmesin. Sıralamasız, kozmetik ödüllü etkinliği misafire açan oyun çıkışta çağırır.

## v0.10.0 (15 Kasım 2026)

- **Kırıcı (sunucu):** günlük oyun, lig ve etkinlik yalnız hesapla. Misafirin `skor_yaz`/`gun_toplami_yaz` çağrısı skor yazmaz, `durum: "misafir"` döner; var olan misafir skorları ve lig üyelikleri silindi (göç `20261120001800`). Seviyeler ve arşiv hesapsız kalır.

### Oyunlar ne yapmalı

- Günlük oyunu, ligi ve etkinliği misafire kapat: girişte giriş penceresini aç. Seviyeler ve arşiv açık kalır.
- Misafire sıralama gösterilebilir ama "sen" satırı olmaz; sonuç ekranında "Sıralamaya girmek için giriş yap" bağlantısı olur.
- Yanıtta `durum: "misafir"` gelirse (eski istemci ya da oturum düştüyse) girişe yönlendir.

## v0.9.0 (15 Kasım 2026)

- **Kırıcı:** misafir/otomatik ad `#` + 5 karakter (ör. `#K7P2X`); `MISAFIR_ADI` ve `misafirAdi()` buna göre. Göç `20261120001700`: var olan 7 karakterli otomatik adlar 5'e çevrildi.
- Giriş ekranı ortak düzenine iki kural (ENTEGRASYON): e-posta alanı kendiliğinden odaklanmaz; webde Google düğmesi e-posta alanıyla aynı boyda ve arayüz dilinde.

### Oyunlar ne yapmalı

- Pakete geç (`#v0.9.0`). Misafir adını kendi sunucusunda üreten oyun (Sticky) 5 karaktere geçer; adı biçime karşı denetleyen yer `MISAFIR_ADI`'yi kullanır.
- Giriş penceresinde e-posta alanına `autofocus`/otomatik odak verme; Google düğmesini `genislik` ve `dil` ile çiz.

## v0.8.1 (15 Kasım 2026)

- `hesap.googleDugmesi`: `genislik` (px, 200–400; Google en çok 400) ve `dil` (verilmezse "tr") seçenekleri (ST-9). Verilmezse davranış aynı.

### Oyunlar ne yapmalı

- Webde Google düğmesi kullanan oyun `dil`'i oyunun o anki diliyle verir; düğme e-posta alanıyla aynı boyda olsun istiyorsa `genislik`'i o alanın genişliğiyle verir.

## v0.8.0 (15 Kasım 2026)

- Günlük sıralamada kurulum başına günde bir hesap: `siralama` paketi gönderime kurulum kimliği (`cihaz`) ekler; `sunucu/mod.ts` `skorYaz` iletir; aynı kurulumdan bugün başka hesap girdiyse `durum: "cihaz"` (skor yazılmaz). `SIRALAMA_METINLERI` (tr/en, uygulama/tarayıcı). `gun_toplami_yaz(..., p_cihaz)`.
- Aynı gün silip yeniden açan hesap o günün günlük sıralamasına girmez (`skor_yaz` 'prova'). `hesabi_sil` ve `hesap_ozeti` istemciye kapandı (OA-1).
- Göçler `20261120001200`…`20261120001500` (canlı ve test).

### Oyunlar ne yapmalı

- Pakete geç (`#v0.8.0`) ve `dogrula-<oyun>` fonksiyonunu yeni `sunucu/mod.ts` ile yeniden yayınla (sürüm etiketi `v0.8.0`).
- Gönderim sonucunda `veri.durum === "cihaz"` ise `SIRALAMA_METINLERI[dil].cihaz.uygulama` (uygulamada) ya da `.tarayici` (webde) metnini bilgi olarak göster.
- Kendi Edge Function'ıyla `gun_toplami_yaz` çağıran oyun (Beat Greedy): istemciden gelen kurulum kimliğini `p_cihaz` olarak ver ve `durum: "cihaz"`ı aynı şekilde göster.

## v0.7.0 (15 Kasım 2026)

- **Kırıcı:** hesaplar oyuncunun gözünde oyun oyun ayrı. `hesap.hesabiSil()` yalnız bu oyunu siler ve oturumu kapatır; kişinin başka oyunda verisi yoksa sunucu giriş kaydını (e-posta, Google/Apple kimliği) da siler. `tamamenSil`, `buOyundanSil`, `hesapOzeti` kaldırıldı.
- Otomatik ad `#` + 7 karakter (ör. `#K7P2X9M`, karışan karakter yok); var olan otomatik adlar çevrildi. `misafirAdi()` ve `MISAFIR_ADI` (misafirini kendi sunucusunda tutan oyun için). Seçilen adlarda `#` olamaz.
- Göç `20261120001100_oyun_ayri_hesap` (canlı ve test). `asyworks.com/hesap-sil/?oyun=<kimlik>` tek oyun için.

### Oyunlar ne yapmalı

- Pakete geç (`#v0.7.0`). Hesap silmede `hesabiSil()` kullan; `tamamenSil`, `hesapOzeti`, doğrudan `hesabi_sil` çağrısını ve başka oyunları anan her metni kaldır.
- Misafire ad sorma; `otomatikAd()` (ya da kendi sunucunda `misafirAdi()`) kullan. Misafire bir satırla söyle: ilerlemesi yalnız bu cihazda ve bu tarayıcıda/uygulamada tutulur; kaybetmemek ve kendi adını seçmek için giriş yapsın.
- Mağaza formlarındaki ve oyun içindeki hesap silme adresini `https://asyworks.com/hesap-sil/?oyun=<kimlik>` yap.

## v0.6.0 (15 Kasım 2026)

- `hesap`: `epostaKoduGonder(eposta, dil?)`. Kod e-postası oyuncunun diliyle gider: "en" → İngilizce, login@asyworks.com; "tr" ya da boş → Türkçe, giris@asyworks.com. Yanıt adresi destek@ / support@asyworks.com.
- Sunucu: Supabase Auth "Send Email Hook" → `giris-epostasi` Edge Function (Resend API). Canlı ve testte açık; yerelde Mailpit'e eski şablon gider. İzinli yönlendirme adreslerine `https://asyworks.com/**` eklendi.

### Oyunlar ne yapmalı

- Pakete geç (`#v0.6.0`). E-posta kodu isterken giriş ekranında seçili dili ver: `hesap.epostaKoduGonder(eposta, dil)`. Oyuncuya ayrıca dil sorulmaz. Tek dilli oyun Türkçeyse değişiklik gerekmez.

## v0.5.0 (14 Kasım 2026)

- `bildirim`: haftalık ek bildirim: `ekPlanla`, `ekAyarla`, `ekAcik`, saf `haftalikSecim` (haftada en çok bir, en çok 4 hafta, isteğe bağlı oynanan günde atla).
- `hesap`: ortak giriş ekranı değerleri: `girisSecenekleri({ platform, apple, misafir })`, `GIRIS_RENKLERI`, `GIRIS_OLCULERI`, `GIRIS_METINLERI`, `GOOGLE_G_SVG`, `APPLE_LOGO_SVG`.
- Sunucu (göçler `20261120000300`…`20261120001000`):
  - Misafir (anonim) oturum ad seçemez, bulut kaydı ve ödül yazamaz (`kalici_hesap_gerekli`); `otomatik_ad` açık. Ödül tavanı oyun başına kullanıcı başına 1000.
  - Hesap devrinde ipucu sayısı düşmez (çoklu küme birleşimi).
  - Sticky: `sticky.rating_uygula` (ST-6), `sticky.siralama(… p_kullanici)` (ST-7).
  - Cihaz bildirim anahtarları `ortak.bildirim_anahtarlari` (ST-8).
  - Halka: HK-17 temizlik, HK-19, HK-20, Web Push kaldırıldı; Beat Greedy profil adı misafire kapalı.

### Oyunlar ne yapmalı
- **Kırıcı:** misafirde `adDegistir`, `bulutKaydi().birlestir` ve ödül eşitlemesi artık hata verir ya da sessizce bekler; bunları yalnız kalıcı hesapta çağırın (misafir `otomatikAd` kullanır). Dört oyun bugün zaten böyle.
- Giriş ekranını `girisSecenekleri` ve `GIRIS_*` değerleriyle hizalayın (`docs/ENTEGRASYON.md` "Giriş ekranı").
- Haftalık bildirimi kendi kodunda kuran oyun `ekPlanla`/`ekAyarla`'ya geçebilir.

## v0.4.0 (13 Kasım 2026)

- Yeni giriş: `@oyun/ortak/sunucu-node` (`jetonDogrulayici`, `servisIstemcisi`): kendi Node sunucusu olan oyunlar için Supabase jeton doğrulama ve servis rolüyle yazma (ST-4).
- Sticky Ten şeması (`20261116000100_sticky.sql`): istatistik, rating, rating günlüğü, ikili sayaç, masa devri; `sticky.oyun_sonu` tek işlem (ST-1); `sticky.siralama` dönemlik sıralama ve `sticky.haftalik_odul` (ST-2); takip (ST-3, oyuna özgü). `ortak.oyunlar('sticky')`, ürün `sticky_deluxe`.

### Oyunlar ne yapmalı
- Kırıcı değişiklik yok. Kendi sunucusu olan oyun `docs/ENTEGRASYON.md` → "Kendi sunucusu olan oyun".

## v0.3.1 (13 Kasım 2026)

Şikâyet düzeltmeleri (`20261115000200_sikayet_duzelt.sql`): yalnız şu anki ada yapılan şikâyetler sayılır; şikâyetçi o oyunda en az `ayarlar.sikayet.en_az_gun` (2) gündür oynamış olmalı; misafirken alınan şikâyetler devirde yeni hesaba taşınır. İstemci API'si değişmedi.

## v0.3.0 (13 Kasım 2026)

- Şikâyet: `hesap.sikayetEt(ad, neden)`; göç `20261115000100_ortak_v03_sikayet.sql` (`ortak.sikayetler`, `ortak.sikayet_et`). Ad şikâyeti eşiğe ulaşınca ad sıfırlanır.
- Halka'nın ortak kaydı (`20261115000000_halka_ortak.sql`): `ortak.oyunlar('halka')`, ürün `paket_tam`, `halka.oyuncu_verisini_sil`.
- Beat Greedy şeması (`20261114000100_sezgi.sql`, `20261114000200_sezgi_silme.sql`); bkz. `docs/GECIS_SEZGI.md`.

### Oyunlar ne yapmalı
- Bağımlılığı `#v0.3.0`'a yükselt; kırıcı değişiklik yok.
- Sıralama ve lig satırlarına "Şikâyet et" seçeneği eklenebilir. Adı sıfırlanan oyuncu `ben().ad === null` görür; oyun ondan yeni ad seçmesini ister.

## v0.2.0 (13 Kasım 2026)

Yeni paketler: `odeme`, `etkinlik`, `geri-bildirim`, `bildirim`. Göç `20261114000000_ortak_v02.sql`: `ortak.urunler`, `ortak.haklar`, `ortak.oduller`, `korumali` depolama kovası; `odeme-webhook` Edge Function (RevenueCat).

### Oyunlar ne yapmalı
- Bağımlılığı `#v0.2.0`'a yükselt. v0.1 API'sinde kırıcı değişiklik yok.
- Satın alma: ürün eşlemesi için bu depoya göç isteği yaz (`ISTEKLER.md`); `docs/ENTEGRASYON.md` → "Ödeme".
- Web için Google girişinde `googleDugmesi` kullan (oyuncu Supabase adresini görmez); yönlendirmeli `webIleGir` yedek.

## v0.1.0 (12 Kasım 2026)

İlk sürüm: `kayit`, `olcum`, `hesap`, `siralama` + `ortak` şeması + Edge Function iskeleti.

### Oyunlar ne yapmalı
- `docs/ENTEGRASYON.md` adımlarını izle; oyun şeması ve `ortak.oyunlar` satırı için bu depoya göç isteği yaz (`ISTEKLER.md`).
- `dogrula-<oyun>` için `sablon/dogrula/` klasörünü kopyala.
