# Önceki sekiz oyun: oturum açılınca yapılacaklar (22 Kasım 2026)

Halka Kelime, Beat Greedy, Sticky Ten, Hop Koala, Ense Nasıl Olsun?, Sahte Masası, Remzle ve Ezber Bozan'ın oturumları kapalıyken alınan ortak kararlar. Oturum açılınca önce bu dosyanın ortak bölümünü ve kendi bölümünü okur, sonra `_ortak/ORTAK_MODUL.md` "Kural" bölümünü ve `_ortak/OYUN_DENETIMI.md` O26–O28'i.

## Ortak iş listesi (Hop Koala hariç)

1. **Kendi yayını** (`docs/YAYIN.md`): deponun köküne `yayin.json` yazılır; yayın `node C:/Projeler/oyunlar/_ortak/oyun-ortak/scripts/yayinla.mjs . <commit>` ile yapılır. Önce `--kuru` koşulur, sonra kurucu onaylar; sunucu işlevi değiştiyse `--islev` eklenir. `yasakMetin` ve `yasakDosya` alanlarına oyunun sızıntı desenleri yazılır (O28). Son kontrolü oyun-ortak oturumu yapar.
2. **Önizleme** (`docs/ONIZLEME.md`, paket v0.22.3):
   - Vitrin, yani ücretsiz katman, her sınıftan ve her moddan örnek içerir; boyutu önerilir, kurucuya sorulur. Vitrin dışı içerik kilitlidir ("Tam sürümde açılacak").
   - `bayraklar.kapali` içindeki günlük, lig, etkinlik, turnuva, sıralama ve düello hiç gösterilmez.
   - `bayraklar.testci` her zaman bütün içeriği açar, yayından sonra da.
   - Oturumsuz misafir bayrakları `hesap.oyunBayraklari()` ile, oturumlu oyuncu `acilis().bayraklar` ile alır.
   - Sunucuda `c.ozellikAcik(...)` sorulur; kendi SQL yolu olan oyun `ortak.etkin_bayraklar` işlevini sorar.
   - Testçi örnekleri: her oyun tipinden en az bir örnek bulunur (günlük, takvimden bağımsız örnek etkinlik ve turnuva, örnek lig görünümü).
   - Hazır olunca oyun-ortak oturumuna "önizlemeye alınabilir" yazılır.
3. **Yayın tarihi ve takvim:**
   - "Gün N", arşivin başı ve etkinlik ile sezon takvimi `bayraklar.yayin_tarihi`'nden hesaplanır.
   - Günlük yükleyici `--baslangic <tarih>` alır; kuru koşuda hangi içeriğin hangi güne gittiğini listeler.
   - İçerik boşa gitmez. Görülmüş birkaç gün sorun değildir; en basit yol seçilir.
   - Özel güne bağlı etkinlik (yılbaşı, bayram) tarihi geçmişse sonraki yılın aynı gününe bırakılır.
4. **e2e testleri:** oyun-test'te oyun önizlemede olunca geçici hesaplar 403 alır. Geçici hesaplar servis anahtarıyla `ortak.testciler`'e eklenir, kullanıcı silinince satır da silinir. Testçi olmayanın 403 aldığı ayrı bir adımla sınanır.
5. **Test derlemesi canlının bayraklarını okumaz** (ÖG-52): yerleşim ve ekran testleri sabit veriyle ya da test Supabase'iyle çalışır.
6. **Ücretli içerik pakette durmaz** (ortak çerçeve §5, satın alma açılmadan önce): pakette yalnız vitrin kalır, gerisi `korumali` kovasından `odeme.korumaliIndir` ile iner. Kova yüklemesi oyun-ortak oturumundadır.
7. **Yayın günü adımları** oyunun belgesine yazılır:
   - `scripts/yayin-temizligi.ts`;
   - oyuna özgü tablolar;
   - takvim kaydırma;
   - noindex'in kaldırılması;
   - korumalı içerik;
   - mağaza.
8. **Canlı içerik yüklemesi** oyun-ortak oturumundadır. Test yüklemelerini oyun oturumu yapabilir.
9. **Görsel ve ses istemleri:** kota bekleyenler listesindeki işler, kurucu kotayı açınca üretilir.

## Oyun oyun

### Halka Kelime
- 1 Aralık yayını **ertelendi**; Halka da önizleme planına uyar, tarih sarkabilir.
- YY-1 (`scripts/yy1-halka.ts`) yeni yayın tarihinin arifesinde koşulur.
- Kış sezonu ve yılbaşı etkinliği takvimi yayın tarihine göre yeniden bağlanır. Yılbaşı geçmişse sonraki yıla kalır.
- Usta Turnuvası ve etkinlik çözümleri (`halka.etkinlik_cozumler`) yayın günü temizliğinde ayrıca ele alınır.
- Kenar (Worker, KV) yolu da önizlemeye uymalı. Halka'nın günlük ve etkinlik dosyaları kenardan geliyor; önizlemede halka açık istekte günlük ve etkinlik verilmemeli.
- KV önizleme yazımı bekliyor (günlük 1000 yazım sınırı yüzünden ertelenmişti).
- Görsel: 1 (kadran çelengi).

### Beat Greedy (sezgi)
- Kendi SQL yolları var (`submit_attempt`, `sezgi.attempts`, lig tabloları). Önizleme denetimi bu SQL işlevlerinde `ortak.etkin_bayraklar('sezgi', auth.uid())` ile yapılır, `ozellikAcik` kullanılmaz.
- Puan v3 30 Kasım'da kendiliğinden başlar; o günün ilk Keşif tesliminde formül 3 görülmeli.
- Etkinlik takvimi 2027-03-28'e kadar; takvim, yayın tarihine göre kaydırma kuralıyla birlikte ele alınır.
- Kurucu canlıda Turnstile ile girişi deneyecek.
- Görsel ve ses yok (mağaza görselleri mağaza paketiyle).

### Sticky Ten
- Çok oyunculu, sunucusu Render'da; seviye yok. Vitrin uygulanmaz.
- Önizlemede gizlenecekler: sıralama (rating), haftalık ödül ve turnuva varsa turnuva.
- Render sunucusu önizlemeyi `ortak.etkin_bayraklar('sticky', kullanıcı)` ile sorar.
- Kurucu canlıda Turnstile ile girişi deneyecek.
- `asyworks-bekci` eşikleri Render planı değişirse güncellenir.

### Hop Koala (istisna)
- Önizleme **uygulanmaz**: bütün içerik açık kalır. Vitrin ve kilit mağazaya yüklenince kurulur.
- Tünel Treni önerisi (Hop Koala'ya yeni turlar): `_ortak/fikirler/2026-11-22-hop-koala-tunel-treni-ekleri.md`.
- Görsel 13, seslendirme 102 satır (kota ve ElevenLabs anahtarı bekliyor). Anahtar şimdilik yalnız Hop Koala'nın `.env` dosyasında; `~/.oyun-ortak/elevenlabs.env` kararı kurucunun.

### Ense Nasıl Olsun?
- Ücretli içerik zaten korumalı kovada. Vitrin olarak mevcut kamuya açık örnek (15 görev) değerlendirilir, boyut kurucuya sorulur.
- Aşama 2 ödeme: RevenueCat `ense_tam_paket` → `ortak.haklar 'tam_paket'`.
- İstek: EN-6 (ücretli içerik sunucuya).
- Görsel 33, ses 72 + 2 müzik.

### Sahte Masası
- Bölümler hesapsız ve ücretsiz; günlük deste hesapla. Vitrin önerisi buna göre yapılır.
- Haftalık deste partileri sürer: oyun 21 deste üretir, yükleme oyun-ortak oturumundan yapılır.
- İstekler: SM-5, SM-6.
- Görsel 20, ses 27 (isteğe bağlı).

### Remzle (sifre-burosu)
- Günlük ve bölüm modu var. Vitrin bölüm modundan seçilir.
- 29 Kasım ilk haftalık rapor: `scripts/haftalik-rapor.ts`, oyun-ortak oturumu koşar.
- 7 Aralık'ta K1 rotasyonu ve kasa ailesi başlar (içerik canlıda yüklü).
- Görsel 13, ses 24.

### Ezber Bozan
- Ücretli içerik korumalı kovada.
- A17 istisnaları sürer:
  - misafir günlüğü oynar, sıralamaya girmez;
  - arşiv yalnız tam açılımla açılır.
- Puan v3 30 Kasım'da başlar.
- Lig sezonu bitince inis_orani için göç yazılır.
- EZ-6: grup içi ödül.
- Görsel 43, ses 27.
