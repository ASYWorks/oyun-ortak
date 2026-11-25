# Canlı işletim

20 Kasım 2026 işletim incelemesi (kurucu). Bu belge yedek, zaman kuralları, zamanlanmış işler, izleme, yayın, büyüme ve
içerik yönetimi için tek başvuru yeridir. Ölçümler 19–20 Kasım; gerçek oyuncu yokken alındı.

## 1. Yedekleme ve kurtarma

**Durum (doğrulandı):** Supabase ücretsiz planında geri yüklenebilir yedek yok. `supabase backups list`, iki projede de `backups: []` ve `pitr_enabled: false` döndürüyor. Kendi yedeğimiz `scripts/yedek.sh`.

| Varlık | Nerede yedekli | Geri yükleme denendi mi |
|---|---|---|
| Veritabanı (bütün şemalar, auth kullanıcıları ve kimlikler dahil) | `sh scripts/yedek.sh canli` → `~/.oyun-ortak/yedek/canli/<UTC>/` (roller, şema, veri, cron) | Evet (20 Kasım), yalıtılmış kapta. Satır sayıları canlıyla birebir |
| Zamanlanmış işler (pg_cron) | Aynı yedekte `cron.sql` (dökümde yok, ayrıca alınır) | Evet, 15/15 iş geri kuruldu |
| Storage nesne kayıtları (`korumali` kovası) | Veri dökümünde satırları var. Dosyaların kendisi YOK | Hayır. Kova içeriği Halka/oyun deposundaki kaynaktan yeniden yüklenir |
| Edge Functions | Git (oyun-ortak, halka-kelime) | Yeniden yayınla: `functions deploy` |
| Yapılandırma | `supabase/config.toml` (git) | `config push` |
| Gizli değerler | Yalnız `~/.oyun-ortak/` (tek kopya) | **Risk:** bu bilgisayar kaybolursa yeniden üretilir: Brevo, Resend, Google, Turnstile, RevenueCat, bilet anahtarı |
| Cloudflare KV (Halka bulmacaları) | Halka deposundaki kaynaktan türetilir | `upload_daily` / `kenar_kv` yeniden yazar |

**Hedef:**
- Veri kaybı en çok 24 saat. Yedek günlük alınır: Windows görevi "oyun-ortak gunluk" her gün 11:00'de (bilgisayar kapalıysa açılınca) `scripts/gunluk.sh` çalıştırır: canlı yedek + canlı sağlık denetimi, günlük `~/.oyun-ortak/yedek/gunluk.log`, sorunda ekrana uyarı penceresi (20 Kasım kuruldu, görevden çalıştırma denendi); oyuncu sayısı büyüyünce Pro'nun günlük yedeği ya da 6 saatte bir yedek.
- Toparlanma en çok 4 saat: yeni proje, geri yükleme, yayın.

**Yedeğin bütünlüğü (D10, 23 Kasım):**
- Döküm önce aynı üst dizinde `.hazirlik-<zaman>-<pid>` dizinine yazılır. Çıktılar doğrulanır: roller, sema, veri ve ozet boş olamaz, cron.sql var olmalı. Sıfır cron işi geçerlidir (`[]`); cron sorgusunun başarısızlığı boru hattında yutulmaz, her satırı `select cron.schedule(` ile başlayan bir metin olmayan yanıt reddedilir.
- Doğrulanan dökümde `.tamam` işareti konur ve tek bir aynı-disk yeniden adlandırmasıyla `<zaman>` adına yayımlanır. Yarım döküm hiçbir zaman `<zaman>` klasörü olarak görünmez; hata çıkışında hazırlık dizini silinir.
- Aynı adda yedek varsa üzerine yazılmaz, betik çıkış 1 ile durur (aynı saniye ya da ikinci çalıştırıcı).
- **Geçerli yedek:** adı `YYYYAAGGTssddssZ`, gerçek dizin (symlink değil), roller/sema/veri.sql ve ozet.txt boş değil, cron.sql gerçek dosya (boş olabilir). `.tamam` varsa gerçek dosya olmalı ve içeriği klasör adıyla eşleşmeli; 23 Kasım öncesi işaretsiz yedekler bu dosyalar tamsa geçerlidir.
- Geçersiz ya da tanınmayan girişler (hazırlık dizinleri dahil) sayılmaz ve silinmez.
- `sh scripts/yedek.sh son canli` ağ kullanmadan son geçerli yedeğin yolunu yazar. `gunluk.sh` panele yalnız bu çalıştırmada başarıyla tamamlanan yedeğin boyutunu bildirir, yedek başarısızsa 0.

**Saklama:**
- Son 14 geçerli yedek (betik daha eskisini siler; yalnız geçerli yedekler sayılır ve silinir).
- Yedekler yalnız kullanıcının klasöründe, Supabase'den bağımsız.
- Öneri: haftada bir kopya harici diske ya da kullanıcının bulut sürücüsüne. Şifreli zip; içinde e-posta ve oturum kayıtları var.

**Geri yükleme adımları (yeni Supabase projesine):**
1. Yeni proje aç (aynı bölge, eu-central-1).
2. `psql --single-transaction -v ON_ERROR_STOP=1 -f roller.sql -f sema.sql -c "SET session_replication_role = replica" -f veri.sql`
   Bağlantı: proje veritabanı URL'si, `supabase_admin` ya da `postgres`.
3. `psql -f cron.sql`: zamanlanmış işler.
4. Gizli değerler `secrets set`, sonra `config push`, sonra Edge Functions `deploy` (oyun-ortak, halka-kelime).
5. Oyunların `VITE_SUPABASE_URL` ve anahtarı yeni projeye. Bu bir istemci yayını demek; oyuncular yeni sürümü alana kadar bekler.

Alternatif: aynı projeye geri dönülecekse önce Supabase'den projeyi geri yüklemesini iste. Ücretsizde mümkün değil.

**Deneme:** yalıtılmış kapta (`public.ecr.aws/supabase/postgres:17.12.0.000`, GoTrue göçleriyle) geri yüklendi. Storage satırları Storage servisi olmadığı için ayrıldı; gerçek projede yüklenir.

## 2. Zaman kuralları

- **Günün sınırı:** İstanbul (Europe/Istanbul; Türkiye 2016'dan beri yaz saati uygulamıyor, UTC+3). Sunucu `ortak.bugun()`. Cihaz saati hiçbir hakkı ve sonucu etkilemez; hile denemeleri ve testlerle doğrulandı.
  - **Kalan risk:** Halka kenarı `istanbulGunu` sabit +3 kullanıyor. Türkiye yaz saatine dönerse yanlış gün hesaplar; Intl ile Europe/Istanbul'a geçilmeli (Halka).
- **Günlük oyun:** başla, gün içinde. Gönderim gece yarısından sonra 10 dakika daha kabul edilir (geç pencere). Dünün cevabı 00:10'da açılır.
  - Gece yarısını geçen oyun: Halka birim testi var (00:09:59 kabul, 00:11 ret).
  - Süre sunucu zamanıyla (deneme kaydı ve nabız) ölçülür.
- **Seri:** İstanbul günlerine göre ardışık günlük skor. Şimdiki seri bugün ya da dün biten zincirdir.
- **Usta Turnuvası durumları:**
  - **açık:** Cumartesi 00:00 – Pazar 23:59.
  - **kapanıyor:** Pazartesi 00:00–00:10, yalnız geç gönderim.
  - **kesinleşti:** cevaplar açık ve Şampiyon ödülü verilmiş; ödül işi Pazartesi 03:15. Tablo yanıtında `kapandi: true`.
  - Önizleme ile kesin sonucu ayıran alan `kapandi`.
- **Eşitlik:** puan eşitse ikincil (süre, sonra hamle) belirler. O da eşitse aynı sıra (rank). Şampiyon kesimi ilk %5'tir (en az 1); kesimdeki eşitlerin hepsi alır. Satır sırası skor kimliğiyle sabittir (deterministik).
- **Geç sonuç:** pencere dışı gönderim 409 alır. Kapanmış haftanın ligine geç skor eklenmez.

## 3. Zamanlanmış işler

`select * from cron.job`; durum `ortak.isletim_durumu()` içinde.

| İş | Zaman (UTC) | Ne yapar | İki kez çalışırsa | Kaçırılırsa |
|---|---|---|---|---|
| ortak-lig-kapat | Pzt 01:00 | Geçmiş haftaların açık grupları | Zararsız (testli) | Sonraki çalışma bütün açık geçmiş grupları kapatır |
| halka-turnuva-odul | Pzt 00:15 (03:15 İst.) | Şampiyon ödülü | Çift ödül yok (testli) | 14 gün geriye bakar, telafi eder |
| sticky-haftalik-odul | Pzt 00:05 (03:05 İst.) | Sticky haftalık ödül | Çift ödül yok (testli) | **Telafi otomatik değil:** `select sticky.haftalik_odul('<Pazartesi>')` elle |
| ortak-saklama, anonim-temizle, odeme-temizle, cron-gecmisi, hiz-temizle | gece / 10 dk | Saklama ve temizlik | Zararsız | Sonraki çalışma telafi eder |
| sezgi-* (5 iş) | dakikalık, saatlik, gece | Beat Greedy | Beat Greedy işi | |

- Gece yarısı yığılmasında ağır iş çalışmaz: haftalık ödüller 03:05 ve 03:15'e alındı (göç 6800).
- İşler tek işlemde çalışır: yarıda kalan iş geri alınır, tekrar çalıştırmak güvenlidir.

## 4. Kesinti ve mobil bağlantı

- **Gönderim:** istemci kuyruğu, aynı runId ile yeniden dener. Yanıt kaybolursa ikinci deneme `tekrar` ve sırayı döner; oyuncu kaydın durumunu öğrenir. Başkasının runId'si `run_id` döner.
  - Durumlar `bekliyor`, `200` ve kalıcı ret olarak ayrılır; Halka bunları gösterir.
- **Toplu yeniden deneme:** kuyruk ilk başarısız denemede durur, döngü yok. Yeniden deneme açılış, ön plana dönüş ve cihazın ağının gelmesiyle yapılır; bunlar oyuncular arasında zamana yayılır. Sunucu kesintisinden sonra eşzamanlı patlama beklenmez.
- **İlerleme:** önce cihazda tutulur. Bulut kaydı sürüm kilitli; iki cihazlı test var, veri kaybı yok. Sunucu kesintisi cihazdaki ilerlemeyi silmez.
- **Çevrimdışı ve çevrimiçi:**
  - Seviyeler ve arşiv çevrimdışı oynanır.
  - Günlük ve turnuva sıralamaya girmek için bağlantı ister; kontrol ve gönderim sunucuda.

## 5. Yayın ve uyumluluk

- **Şema değişikliği:** yalnız `supabase/migrations` içinden, sürümlü dosyalarla.
  - Önce geriye uyumlu ekle (yeni alan veya işlev). Eski alanı ve işlevi en az bir istemci sürümü boyunca koru (örnek: 5700'de nabız korundu).
  - Kaldırma ayrı ve sonraki bir göçte.
- **Kilit etkisi:** büyük tabloda `create index` yazmaları kilitler.
  - Satır sayısı 100 binin üstündeyse indeksi göçten önce `create index concurrently` ile elle oluştur (işlem dışında). Göçte `if not exists` kullan.
  - Sütun ekleme varsayılansız ya da sabit varsayılanla anlıktır.
- **Geri alma:**
  - İşlev: önceki commit'ten `functions deploy`.
  - Göç: geri alınmaz, ileri düzeltme göçü yazılır (her göç `create or replace` ile önceki gövdeye dönebilir).
  - Yapılandırma: önceki `config.toml` ile `config push`.
  - İstemci: `VITE_*` bayrağı ya da önceki sürüm.
- **Sunucu kontrollü durdurma:** `ortak.oyunlar.ayarlar.bayraklar` açılışta (`hesap.acilis().bayraklar`) döner.
  - `kapali: ["turnuva"]`: özelliği kapat. `asgari_surum`: zorunlu güncelleme. `duyuru`: oyuncuya kısa metin.
  - Oyun anlamı oyunda: Halka okumalı. Sunucu tarafı reddi için dogrula-halka da bayrağa bakmalı.
- **Test ve canlı ayrımı:** ayrı Supabase projeleri, anahtarlar ve gizli değerler.
  - **Kalan risk:** Halka kenar KV ad alanı önizleme ve canlıda ortak. Test amaçlı yükleme canlı bulmacaları değiştirebilir; önizleme için ayrı KV önerilir (Halka).

## 6. İzleme ve uyarılar

`node scripts/saglik.ts canli`: salt okunur. Çıkış 0 temiz, 1 uyarı, 2 denetlenemedi; 2 de uyarıdır, izleme çalışmıyor demektir.

| Uyarı | Eşik | Müdahale |
|---|---|---|
| Zamanlanmış iş başarısız ya da gecikti | 24 saatte ≥1 hata; beklenen aralık aşıldı | Hatayı oku. Ödül ve kapanış işleri tekrarlanabilir, elle bir kez çalıştır |
| Bugünün Halka bulmacası yok | Var değil | Halka `upload_daily` (önce test). Oyuncular bugünü açamıyor |
| İçerik azalıyor | Halka < 14 gün, turnuva < 7 gün, BG < 7 gün | İlgili oyun oturumu içerik üretip yükler |
| Kapanmamış geçmiş lig grubu | > 0 (Pazartesi 05:00 İstanbul'dan sonra) | `select ortak.lig_kapat();` |
| Ödülsüz biten turnuva | > 0 | `select halka.turnuva_odul_ver();` |
| Veritabanı boyutu | > 400 MB (ücretsiz sınır 500 MB) | §7 saklama ya da Pro |

- **İşlem kimliği:** gönderimde `runId` istemciden sunucuya ve skora kadar taşınır (`ortak.skorlar.run_id`).
- **Günlüklerde jeton, parola ya da kişisel veri yok:**
  - Edge hata iletisi ayıklanır (v0.18.1).
  - Kenar kontrolü hiç günlük yazmaz.
- **Kalan:**
  - Sağlık betiği günlük görevle çalışıyor (yukarı bak). Bilgisayar günlerce kapalıysa ne yedek ne izleme olur.
  - Edge 5xx oranı ve Cloudflare 429 sayısı betikte yok; Supabase ve Cloudflare panellerinden bakılır.

## 7. Büyüme ve maliyet

Ölçülen satır boyutları (20 Kasım, canlı; indeksle yaklaşık 2 katı):

| Tablo | Satır başına | Oyuncu başına büyüme |
|---|---|---|
| ortak.skorlar | ~560 B | Oynadığı her gün 1 satır (+ turnuvada 1). 90 günden eskinin ayrıntısı kırpılır |
| ortak.denemeler | ~145 B | Günde 1; 90 günde silinir |
| ortak.kayitlar | ~1,3 KB | Oyuncu başına 1 (büyürse 256 KB tavan) |
| ortak.oyuncular / oduller | ~125 B | Oyuncu başına 1 / ödül başına 1 |
| auth.users + sessions + refresh_tokens | ~350 + 200 + 150 B | Yenileme jetonları oturumla büyür. **Doğrulanmadı:** büyük ölçekte GoTrue temizliği izlenecek |
| cron.job_run_details | ~133 B | Günde ~1.700 satır; 7 günde silinir |

**Aylık tahmin.** Varsayımlar: oyuncu günde 1 günlük oynar; skor ve indeksi ~1,5 KB/oyuncu-gün; Halka oyununda ~30 kontrol; oturum başına ~10 PostHog olayı.

| Günlük aktif oyuncu | DB büyümesi/ay | Edge çağrısı/ay (ücretsiz 500 bin) | Kenar istek/gün (ücretsiz 100 bin) | PostHog olay/ay (ücretsiz 1 M) |
|---|---|---|---|---|
| 1.000 | ~50 MB | ~60 bin | ~30 bin | ~300 bin |
| 3.000 | ~150 MB | ~180 bin | ~90 bin (sınırda) | ~900 bin (sınırda) |
| 10.000 | ~500 MB (ücretsiz disk 500 MB) | ~600 bin (aşar) | ~300 bin (aşar) | ~3 M (aşar) |

- **Saklama politikası:**
  - Skorlar kalıcı; profil, itiraz ve ödül incelemesi için gerekli. Ayrıntı 90 günde kırpılır, toplamlar kalır.
  - Denemeler 90 gün, ödeme olayları 180 gün (iade penceresi), cron geçmişi 7 gün, hız sınırı 2 saat, misafir 90 gün hareketsiz.
  - Yönetim kaydı silinmez (küçük).
- **Harcama:** ücretsiz planlarda fatura yok, dolunca hizmet kısıtlanır. Supabase Pro'da harcama sınırı (spend cap) ayrı bir ayardır; fatura uyarısı harcamayı durdurmaz. Pro'ya geçince spend cap açık kalmalı.

## 8. Hesap ve ilerleme

Testli olanlar: misafirden kalıcı hesaba geçiş (devir), iki cihaz (bulut kaydı), çıkışta ilerlemenin hesaba bağlı tutulması (O15), oyun bazında hesap silme.

- **Yeniden kurulum:**
  - Misafir ilerlemesi cihazdaydı, kaybolur. Tasarım gereği; misafir uyarılır.
  - Hesaplı oyuncu girişte buluttan geri alır.
- **Oturum süresi:** Supabase yenileme jetonuyla uzar. Süresi dolarsa yeniden giriş; ilerleme cihazda ve bulutta kalır.
- **Hesap silme:** o oyunun oyuncu satırı, kaydı, skorları, ödülleri ve hakları silinir. Ad 30 gün kilitli kalır. Başka oyunlarda veri kalmadıysa auth kullanıcısı da silinir.
- **E-posta ile giriş:** canlıda gerçek teslimat denendi (19 Kasım, Turnstile açıkken `/otp 200`, `/verify 200`). Brevo günde 300; dolunca Google ve Apple çalışır.

## 9. İçerik ve yönetim

- **Açılmış bulmaca koruması (6800):** bugün ya da geçmiş günün halkası, cevabı, çözümü, kuralı ya da başlangıcı sessizce değiştirilemez; işlem reddedilir. Aynı içeriğin yeniden yazılması serbesttir.
  - **Bilinçli düzeltme:** aynı oturumda `set halka.duzeltme = 'evet'`, ardından düzeltme. Değişiklik yönetim kaydına düşer.
  - **Önceki oyuncular:** o günün skorları ve ödülleri silinmez, yeniden hesaplanmaz. Sorun bildirilir, gerekirse elle değerlendirilir.
- **Yönetim kaydı (6800):** bulmaca, oyun ayarı, ürün ve hak değişikliklerinde zaman, rol, uygulama, tablo, anahtar, değişen sütunlar ve eski/yeni özet. Yalnız gerçekten değişen satır yazılır.
- **İçerik yetersizliği:** sağlık betiği uyarır (§6).
- **Yayın öncesi içerik doğrulaması** (eksik, yinelenen, geçersiz cevap, çözümsüz): Halka üretim betiklerinde. Tek bir "yüklemeden önce doğrula" adımı Halka'ya önerildi.
- **Satın alma:** RevenueCat webhook'u imza (sır) ile doğrulanıyor. Aynı olay bir kez işleniyor, iade ve devir testli (`tests/sunucu/v02.test.ts`).
