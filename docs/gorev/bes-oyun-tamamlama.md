# Görev: beş oyunun ortak yapıya göre tamamlanması (kurucu, 26 Kasım 2026)

Oyunlar: **El Bitir** (el-bitir), **Kayan Yük** (kayan-yuk), **Kelime Köprüsü** (kelime-koprusu), **Koku İzi** (koku-izi), **Kulis** (sandik-ustasi). Takip: `docs/takip/bes-oyun.md` (oyun-ortak oturumu günceller).

## A. Ortak yapı adımları (her oyun kendi oturumunda)

1. `_ortak/OYUN_DENETIMI.md`'nin bütün bölümlerini (1 arayüz ve sanat yönü, 2 pazar, 3 ortak altyapı ve kesin kararlar, 3b hız, 3c K1–K10 kabul senaryoları, 4 metin ve marka, 5 beceriler) oyunun `docs/DENETIM.md`'sinde madde madde **kanıtla** işaretle: UYGULANDI (kanıt: dosya/komut/ölçüm) / KISMEN / YOK / BU AŞAMADA DEĞİL (gerekçe). Yazılı ama uygulanmamış kural UYGULANDI sayılmaz.
2. Özellikle bak: ONIZLEME (vitrin, bayraklar, testçi; ek kural 7), ADIL_PUAN/RATING ve `docs/PUAN.md`, `docs/BILDIRIM.md`, yasal ekran (A14), dil geçişi (A15), oyun oyun hesap ve misafir adı (A16), günlük hesapla (A17), ölçüm kapatma (O12), hesap ayrımı (O15), yakınlaştırma yok (A5), açık dil (M1), ad kuralı, `com.asyworks.<oyun>`, kişisel ad hiçbir yerde, `@oyun/ortak` son sürüm (v0.23.6), KABUL_MATRISI satırı (K1–K10).
3. Eksik ve hatalıları **düzelt**. Ağır iş (üretim, kapasite, tarayıcı, Gradle) öncesi oyun-ortak oturumundan sıra iste. Kurucu kararı gerekenleri ACIK_KONULAR'a yaz ve seçenekli sor (öneri ilk seçenek). Yayın kurucu onayıyla.
4. Bitince oyun-ortak oturumuna rapor: "A tamam" + kalan BU AŞAMADA DEĞİL maddeleri (en çok 5 satır).

Koku İzi için A: ön çalışma kapıları (YENI_OYUN adım 3) + tam üretim bitişi; Aşama 0'a geçiş kurucunun sanat yönü onayıyla (A-5). Kulis Aşama 2'de: A aşamasına uygun maddeleri kapsar.

## B. Görsel ve ses istemleri (kota açılınca üretilecek)

Her oyun profesyonel görünüm için gereken görsel ve sesleri **istem olarak** hazırlar, üretmez:
- `docs/gorsel/ISTEMLER.md`: her dosya için ad, amaç, öncelik (1–3), boyut ve biçim, hedef yol, istem metni, referans; model GPT Sol 6.2 (logo ve mağaza görseli kurucu isterse Astra 6). Yazı, logo, gerçek kişi yok.
- `docs/ses/ISTEMLER.md`: ses olayı, öncelik, süre, biçim (mono, 44,1 kHz, ogg/mp3, hedef boyut), hedef yol, istem, aday sayısı; ElevenLabs, çevrimdışı; müzik için lisans kurucu onayı.
- Rapor: "B tamam: görsel N dosya / M aday, ses N dosya / M aday, öncelik 1 sayısı".

## C. Bağımsız inceleme (A bitince, kurucu kararı)

Oyun-ortak oturumu her oyun için ayrı bir **Fable 5.2** ajanı açar (kurucu açıkça istedi). Ajan ortak yapıya göre eksik, hatalı ve sorunlu kalanları bulur; bulgular oyunun oturumuna iş olarak verilir, oturum düzeltir ya da gerekçeyle reddeder.

## Kurallar
Fable yalnız C'de. Commit ASYWorks kimliğiyle. Rapor kısa. Makine sırası oyun-ortak oturumunda.
