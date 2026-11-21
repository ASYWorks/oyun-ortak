# Entegrasyon: bir oyun oyun-ortak'a nasıl bağlanır

Okuyucu: oyun deposunda çalışan oturum (Aşama 1'e gelmiş oyun). Önce `_ortak/ORTAK_MODUL.md`'deki "Mevcut kod ne olacak" bölümünü oku.

## Sıra

1. **Envanter.** Oyundaki altyapı kodunu ve servisleri listele: hesap/giriş, skor, sıralama, yedek, ölçüm, push, ödeme; Vercel API, Neon, Upstash, Worker, kendi sunucu.
2. **Eşleme.** Her parçanın paketteki karşılığını yaz (aşağıdaki tablo). Karşılığı olmayanı bu depodaki `ISTEKLER.md`'ye ekle: oyun, paket, istek, neden, kabul ölçütü. Oyuna özgü kodu ISTEKLER'e kopyalama.
3. **Sunucu tarafı (bu depoda, istekle).** Oyunun `ortak.oyunlar` satırı ve varsa oyun şeması bu deponun `supabase/migrations/` klasörüne göç olarak eklenir. Oyun deposu veritabanına göç yazmaz.
4. **`src/altyapi/`.** İnce uyarlama katmanını yaz. Oyun kodu paketi yalnız buradan çağırır.
5. **`dogrula-<oyun>`.** `sablon/dogrula/` klasörünü oyun deposunda `supabase/functions/dogrula-<oyun>/` altına kopyala, motoru bağla.
6. **Testler** geçince eski altyapıyı ve servisleri kaldır. Vercel bağlantısını kopar, Cloudflare Pages'e taşı.
7. Canlı kullanıcısı olan oyunda veri taşıma planı ayrı yazılır (Halka için `docs/GECIS.md`).

## Eşleme tablosu

| Eski | Paketteki karşılığı |
| --- | --- |
| localStorage kaydı, JSON dosya kaydı | `@oyun/ortak/kayit` → `kayitDeposu` (iki anahtarlı yazım, yedekten açma, `iceAl` ile eski anahtardan bir kez içe alma) |
| Çıkışta kayıt temizleme, hesap değişiminde yerel veri | `@oyun/ortak/kayit` → `sahipDenetle({ depo, oyun, anahtarlar, kimlik, birlestir })` açılışta ve her oturum değişiminde; çıkış ve silmede `hesapDegistir({ ..., eski, yeni: "", yedekle })`. Önce açık oyunu kaydedip kapat, eşitlemeyi durdur (nesil sayacı), sonra sayfayı yeniden aç (O15). `iceAl` kullanan kaydın eski anahtarı da `anahtarlar`da olmalı. Bekleyen `kayit.yaz` Promise'leri çağrıdan önce beklenir (`void yaz()` tuzağı) |
| Cihaz kimliği, test kodu (`?t=`) | `cihazKimligi(depo, testKodu)` |
| E-posta kodu, kendi oturum jetonu | `@oyun/ortak/hesap` (Supabase Auth: anonim → Google/Apple/e-posta kodu) |
| Misafir ilerlemesini hesaba bağlama | Devir otomatik; yerel kayıt `bulutKaydi().birlestir(yerel, oyununBirlestirmeIslevi)` |
| Takma ad, küfür filtresi, 30 gün | `adDegistir` (yalnız giriş yapan oyuncu), `otomatikAd()` (sunucu üretir: `#` + 5 karakter, ör. `#K7P2X`); kurallar `ortak.oyunlar.ayarlar.ad`. Misafire ad sorulmaz; oyun kendi sunucusunda tutuyorsa `misafirAdi()` aynı biçimi üretir. Ad her oyunda ayrı ve benzersizdir; benzersizlik Türkçe katlanmış anahtarla (`ortak.ad_anahtari`: "Ayşe" = "AYSE" = "ayse"). Kendi ad tablosunu tutan oyun adı `ortak.oyuncular`a yansıtır (ör. `sezgi.ad_denetle`), ayrı tekillik kuralı yazmaz |
| Bulut yedeği / eşitleme blob'u | `bulutKaydi()` (≤256 KB, iyimser kilit) |
| Skor gönderimi, yeniden oynatma, runId | `@oyun/ortak/siralama` → `gonder(govde)` (çevrimdışı kuyruk) + `dogrula-<oyun>` |
| Sunucuda durum tutan deneme | `c.deneme(anahtar)` (örnek: `supabase/functions/dogrula-deneme`, `olay` dalı) |
| Günlük sıralama, ilk N + çevre | `tablo("gunluk", gun)` |
| Haftalık lig, kademe | `lig()`; ayarlar `ortak.oyunlar.ayarlar.lig`; kapanış pg_cron |
| Olay kaydı (Neon, D1, Supabase tablosu) | `@oyun/ortak/olcum` → PostHog (AB); oyuna özgü olaylar `uzantiOlaylar` |
| Günlük, lig ve sıralamalı etkinlik yalnız hesapla | Seviyeler ve arşiv hesapsız (misafir) oynanır; günlük oyun, lig ve sıralamalı etkinlik hesap ister. Sıralaması olmayan, ödülü yalnız kozmetik olan etkinlik misafire açık olabilir: ilerleme cihazda, girişte hesaba taşınır (`etkinlik.esitle`), çıkışta cihazdan silinir (`etkinlik.yerelTemizle()`; Beat Greedy). Misafir sıralamaya hiç girmez: `skor_yaz` ve `gun_toplami_yaz` misafirde skor yazmaz, `durum: "misafir"` döner. Oyun günlük/lig/etkinlik girişinde misafire giriş penceresini açar ("Günlük bulmaca ve lig için giriş yap"); seviyeler ve arşiv kilitlenmez (15 Kasım 2026) |
| Ortak ad kuralı | Ad 3–20 karakter; harf (Türkçe dahil), rakam, `_` ve `.`; boşluk yok; `_` ve `.` başta, sonda ve yan yana olamaz; en az bir harf. Oyun kendi kuralını yazmaz: ad adımında `AD_METINLERI[dil].kural` gösterilir, yazarken `adBicimiUygun` denetler, son karar sunucunun (`ortak.ad_bicimi`; uygunsuz ve alınmış ad da orada). Kendi sunucusunda ad tutan oyun aynı kuralı uygular (kurucu, 15 Kasım 2026) |
| Sıralamada seçilmiş ad şart | Giriş yapan oyuncu sıralamaya girmeden önce kendine ad seçer: girişten sonra `hesap.ben()` `ad_otomatik: true` diyorsa oyun "Sıralamada görünecek adın" adımını açar (`adDegistir`); ad seçilmeden sıralamaya girilmez. Sunucu zorlar: adı otomatik olan hesabın günlük ve etkinlik skoru yazılmaz, `durum: "ad_gerekli"` döner; oyun ad seçtirip aynı gönderimi yineler (aynı runId tek skor üretir). Sıralamada `#XXXXX` gibi kodlu ad görünmez (kurucu, 15 Kasım 2026) |
| Kurulum başına günde bir hesap (günlük sıralama) | `siralama` paketi her gönderime kurulumun rastgele kimliğini (`cihaz`) ekler; `sunucu/mod.ts` `skorYaz` bunu `skor_yaz`a verir. Bu kurulumdan bugün başka hesap girdiyse yanıt `durum: "cihaz"` olur, skor sıralamaya yazılmaz; oyun `SIRALAMA_METINLERI[dil].cihaz.uygulama` ya da `.tarayici` metnini gösterir (hata gibi değil, bilgi olarak). Aynı telefondaki uygulama ve tarayıcı ayrı kurulumdur. Kendi işleviyle `gun_toplami_yaz` çağıran oyun `p_cihaz`ı istemcinin gönderdiği kimlikle verir; kendi günlük tabloları olan oyun her teslimde kurulumu ayırır ve başka hesaba ait kurulumdaki teslimi tablolarda saymaz (Beat Greedy: `sezgi.kurulum_isaretle`). Kapalı test kurulumları (test koduyla açılan) muaftır: kimlik göndermez ya da UUID dışı gönderir, sunucu yok sayar (kurucu, 15 Kasım 2026) |
| Yakınlaştırma yok (A5) | Hiçbir oyunda yakınlaştırma ve sistem yazısıyla büyüme yok. Web: viewport `width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no`; `html { -webkit-text-size-adjust: 100%; text-size-adjust: 100%; }`. Capacitor Android: `MainActivity`'de `getBridge().getWebView().getSettings().setTextZoom(100)`. TWA (Chrome) kapatamaz; Chrome'un "yakınlaştırmayı zorla" ayarı oyuncunun tercihi. Expo/React Native: React 19'da `Text.defaultProps` çalışmadığı için `metro.config.js` `resolveRequest` ile oyunun kendi kodundaki `react-native` içe aktarımı bir sarmalayıcıya yönlenir (`export * from "react-native"`, `Text` ve `TextInput` `allowFontScaling={false}` ile sarılı); kütüphaneler gerçek modülü alır (Beat Greedy `src/ui/rn`) (15 Kasım 2026) |
| Ölçüm kapatma ve geri bildirim | Ayarlarda "Kullanım ölçümü" anahtarı: `olcum.ayarla(acik)` / `olcum.acik()` (varsayılan açık; kapalıyken olay gitmez, kuyruk silinir, tercih cihazda kalır). Kalıcı "Geri bildirim gönder" formu: `geriBildirimGonder(olcum, tur, metin, { ekran })` (tür: hata, oneri, bulmaca, diger; en çok 200 karakter). Oyuncu açıkça gönderdiği için ölçüm kapalıyken de gider, ama adsız ve cihaz kimliği olmadan (`olcum.adsizOlay`) (15 Kasım 2026) |
| Uygulamada (yerel) Google ve Apple girişi | Paket yerel eklenti içermez; oyun eklentiden aldığı kimlik jetonunu `hesap.idTokenIleGir("google" \| "apple", jeton, nonce)` ile verir. Capacitor: `@capgo/capacitor-social-login` (Google + Apple). Expo: `@react-native-google-signin/google-signin` + `expo-apple-authentication`. Google için oyun-ortak Google Cloud projesinde her oyuna Android istemcisi (paket adı `com.asyworks.<oyun>` + imza SHA-1) ve iOS istemcisi açılır; istemci kimlikleri Supabase Google sağlayıcısının `client_id` listesine virgülle eklenir (config.toml). Apple için Apple geliştirici hesabı ve Supabase Apple sağlayıcısı gerekir. Yerel Google girişinde eklentiye `webClientId` olarak WEB istemcisi verilir (`104092866938-o606eoqcqkjh38mdo00kg8baate5kcoi`); jetonun hedefi odur, Supabase onu kabul eder; Android istemcisi koda yazılmaz, yalnız paket + imza eşleşmesi içindir. Açılan Android istemcileri: Beat Greedy `com.asyworks.beatgreedy` yükleme anahtarı (`104092866938-fc4vvdfrru2mfrr9f3qcaehd1hrvs5qt`, 15 Kasım 2026); Sticky Ten `com.asyworks.stickyten` yükleme anahtarı (`104092866938-c337884c2u5m4maq1eg64j6u7su4bcrp`, 15 Kasım 2026). Play App Signing açılınca her oyuna Play imza SHA-1'iyle ikinci istemci açılır. Herkeste aynı olan Expo/RN debug anahtarı eklenmez |
| Hesap silme | `hesabiSil()`: yalnız bu oyun; kişinin başka oyunda verisi yoksa sunucu giriş kaydını da siler; ardından oturum kapanır. Web: `asyworks.com/hesap-sil/?oyun=<kimlik>` (mağaza formundaki silme adresi bu). Hesaplar oyuncunun gözünde oyun oyun ayrıdır: hiçbir ekranda, e-postada ya da silme akışında başka oyun anılmaz; "tümünü sil" ve oyun listesi yok (15 Kasım 2026) |
| Satın alma, "paket açık mı" kilidi, geri yükleme | `@oyun/ortak/odeme` (RevenueCat; aşağıda "Ödeme") |
| Ücretli dosyaların herkese açık durması | `korumali` kovası + `odeme.korumaliIndir(hak, dosya)` |
| Etkinlik takvimi, sezon, albüm ödülleri | `@oyun/ortak/etkinlik` (takvim opak; ödül eşitleme) |
| Kapalı test anketi | `@oyun/ortak/geri-bildirim` (karar + ölçüme gönderim; arayüz oyunda) |
| Günlük hatırlatma | `@oyun/ortak/bildirim` (yerel bildirim; sunucu push sonra) |

## Kurulum

```jsonc
// package.json
"dependencies": {
  "@oyun/ortak": "github:ASYWorks/oyun-ortak#v0.1.0",
  "@supabase/supabase-js": "^2.119.0"
}
```

Yerelde iki depoyu birlikte geliştirirken `npm link ../_ortak/oyun-ortak` kullanılabilir. Bu bağlantı commit'e girmez.

Ortak değerler (hepsi herkese açık, uygulamaya gömülür):

| | `oyun-canli` (yayın) | `oyun-test` (önizleme) |
| --- | --- | --- |
| Supabase adresi | `https://qzxchutjzhyzzaoxzroh.supabase.co` | `https://vbygbyurswjjmiqrhvmo.supabase.co` |
| Anon / publishable anahtar | `npx supabase projects api-keys --remote=qzxchutjzhyzzaoxzroh` | `npx supabase projects api-keys --remote=vbygbyurswjjmiqrhvmo` |
| PostHog (AB, tek proje) | `phc_xLYVrxm9z6jsgXrGDpbUAKBypFX9qv5mhwVctX4QQia9` | Aynı anahtar; test olayları cihaz kimliğindeki `t-<kod>` ile ayrılır |

Tek ayar dosyası `src/oyun.config.ts`. Supabase adresi ve anon anahtarı gizli değildir, ama ortam değişkeninden gelir. Böylece önizleme `oyun-test`'e, yayın `oyun-canli`'ya bağlanır.

```ts
export const oyunConfig = {
  oyunId: "halka",
  supabaseUrl: import.meta.env.VITE_SUPABASE_URL,
  supabaseAnon: import.meta.env.VITE_SUPABASE_ANON_KEY,
  posthogAnahtar: import.meta.env.VITE_POSTHOG_KEY ?? "", // boşsa ölçüm kapalı
  uzantiOlaylar: ["league_joined", "album_card"],
} as const;
```

Örnek `src/altyapi/index.ts` (Capacitor + web):

```ts
import { createClient } from "@supabase/supabase-js";
import { Preferences } from "@capacitor/preferences";
import { Capacitor } from "@capacitor/core";
import { capacitorDepo, webDepo, cihazKimligi, kayitDeposu } from "@oyun/ortak/kayit";
import { hesapBaslat } from "@oyun/ortak/hesap";
import { siralamaBaslat } from "@oyun/ortak/siralama";
import { olcumBaslat } from "@oyun/ortak/olcum";
import { oyunConfig as k } from "../oyun.config";

const depo = Capacitor.isNativePlatform() ? capacitorDepo(Preferences) : webDepo();
export const supabase = createClient(k.supabaseUrl, k.supabaseAnon);
export const hesap = hesapBaslat({ supabase, oyunId: k.oyunId, depo });
export const siralama = siralamaBaslat({ supabase, oyunId: k.oyunId, depo });
export const kayit = kayitDeposu({ depo, anahtar: `${k.oyunId}:kayit`, surum: 1, bos: () => ({}) /* , iceAl */ });
export const olcum = olcumBaslat({
  oyunId: k.oyunId, surum: __SURUM__, platform: Capacitor.getPlatform() as "web" | "android" | "ios",
  anahtar: k.posthogAnahtar, cihaz: await cihazKimligi(depo, new URLSearchParams(location.search).get("t")),
  depo, uzantiOlaylar: k.uzantiOlaylar,
});
```

Expo (Beat Greedy): depo, AsyncStorage'dan `{ oku: getItem, yaz: setItem, sil: removeItem }` ile verilir. Geri kalanı aynıdır.

### Giriş

- **Android/iOS:** yerel Google/Apple eklentisinden kimlik jetonu alınır, `hesap.idTokenIleGir("google" | "apple", token, nonce)` çağrılır. Eklenti oyunun bağımlılığıdır, paketin değil.
- **Web:** `hesap.webIleGir("google", donusAdresi)`. Dönüşte, açılışta `hesap.webDonusunuTamamla()` çağrılır. Oturum değişimini dinleyen oyun `SIGNED_IN` ile birlikte `INITIAL_SESSION` olayını da işler: dönüşte oturum, abonelik bağlanmadan kurulursa yalnız `INITIAL_SESSION` gelir; yalnız `SIGNED_IN` dinlenirse ilk denemede giriş ekranında kalınır (Sticky Ten, 15 Kasım 2026).
- **E-posta kodu (yedek):** `epostaKoduGonder(eposta, dil)`, ardından `epostaKoduIleGir`. `dil` oyuncunun o anki oyun dilidir: "en" verilirse kod İngilizce e-postayla login@asyworks.com'dan, "tr" ya da boşsa Türkçe e-postayla giris@asyworks.com'dan gider (bulutta `giris-epostasi` kancası; yerelde Mailpit'e eski şablon gider).
- **Ortak akış:**
  1. Oyuncu misafir başlar. `anonimGir()` ilk çevrimiçi işte çağrılır; `siralama.gonder` bunu kendisi yapar.
  2. Girişten sonra `bulutKaydi().birlestir(yerel, birlestir)` çağrılır ve dönen `ozet` oyuncuya gösterilir.
  3. Ardından `baglamaOdulu()` çağrılır.
- Google ve Apple düğmeleri öne çıkarılır; e-posta kodu "başka yol" altında durur (kesin karar).

#### Giriş düğmeleri: marka kuralları (zorunlu)

Bu düğmeler oyunun paletine boyanmaz ve logoları değiştirilmez. Kurallara uymayan düğme Google OAuth doğrulamasında ve mağaza incelemesinde geri çevrilme nedeni olur. Düğme bileşeni oyunda yaşar, paket arayüz çizmez. Örnek uygulama: sezgi `apps/mobile/src/ui/GoogleButton.tsx`.

**Google** ([Google Identity marka kuralları](https://developers.google.com/identity/branding-guidelines)):

| | Koyu tema | Açık tema |
|---|---|---|
| Zemin | `#131314` | `#FFFFFF` |
| 1 px kenar | `#8E918F` | `#747775` |
| Yazı | `#E3E3E3` | `#1F1F1F` |

- Standart dört renkli "G" kullanılır (`#EA4335`, `#4285F4`, `#FBBC05`, `#34A853`). Logo 20 px boyunda olur ve yazıdan 10 px önde durur.
- Yazı Roboto Medium 14 olur. Roboto yalnız bu düğme için yüklenir.
- Köşe yarıçapı 4 px. Yükseklik en az 40; dokunma hedefi için 44 önerilir.
- Metin "Google ile devam et" ya da "Continue with Google" olur.

**Apple** ([Sign in with Apple HIG](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)):

- Üç biçimden biri kullanılır: siyah, beyaz ya da beyaz zemin üstüne siyah kenarlı. Başka renk kullanılmaz.
- Apple logosu ve "Apple ile devam et" ya da "Continue with Apple" metni kullanılır. iOS'ta sistemin `ASAuthorizationAppleIDButton` düğmesi tercih edilir.
- Düğme Google düğmesiyle aynı boyda olur ve ondan daha az öne çıkarılmaz. App Store 4.8 kuralı gereği, iOS'ta Google girişi sunan oyun Apple girişini de sunar.

#### Giriş ekranı: ortak düzen (zorunlu, giriş isteyen her oyunda; 14 Kasım 2026)

- **Misafir başlar.** Oyuncu giriş yapmadan oynar; sunucuya ilk iş gerektiğinde anonim oturum açılır (`hesap.anonimGir`). Giriş, oyuncu bir hesap özelliğine (sıralamada ad, cihazlar arası kayıt, lig) dokununca ya da ödülle önerilir; zorunlu kayıt yok.
- **Seçenekler ve sıra ortak:** `girisSecenekleri({ platform, apple, misafir })` (`@oyun/ortak/hesap`). iOS'ta Apple ve Google aynı boyda öne çıkar; Android ve webde Google öne çıkar (Apple istenirse eklenir); e-posta kodu altta ve daha sade bir yedektir; en altta "Misafir olarak devam et". **İstisna:** oyun zaten misafir başlıyorsa, giriş ekranı yalnız oyuncu isteyince açılıyorsa ve üstte Geri düğmesi varsa misafir düğmesi konmaz (`misafir: false`), çünkü Geri ile aynı işi yapar (kurucu, 15 Kasım 2026; Beat Greedy, Halka Kelime).
- **Değerler ortak:** düğme renkleri, ölçüleri, logoları ve metinleri `GIRIS_RENKLERI`, `GIRIS_OLCULERI`, `GOOGLE_G_SVG`, `APPLE_LOGO_SVG`, `GIRIS_METINLERI`'nden alınır; oyun düğmeyi kendi çatısında (web, React Native) çizer ama logo ve renkleri yeniden yazmaz. Webde Google'ın kendi düğmesi (`googleDugmesi`) de kullanılabilir.
- **Akış ortak:** `idTokenIleGir` / `webIleGir` (Google, Apple), `epostaKoduGonder` + `epostaKoduIleGir`; misafir ilerlemesi her yolda devir koduyla hesaba taşınır. Oyun giriş akışını kendisi yeniden yazmaz.
- **Klavye kendiliğinden açılmaz:** giriş penceresi açılınca e-posta alanı odaklanmaz (telefonda klavye açılmasın, oyuncu önce Google/Apple'a bassın); klavye yalnız alana dokununca ya da oyuncu açıkça "e-postayla" seçince açılır (15 Kasım 2026).
- **Webde Google düğmesi e-posta alanıyla aynı boyda ve arayüz dilinde:** `googleDugmesi(..., { genislik, dil })`; formun içerik genişliği (düğme ve alanların genişliği; kartın iç boşluğu hariç) en çok 400 px (Google düğmesinin sınırı) ki boylar eşit kalsın; dil ya da ekran yönü değişince düğme yeniden çizilir (15 Kasım 2026).
- Ekranın yerleşimi ve çevresi (başlık, açıklama, arka plan) oyunun sanat yönüne aittir; düğmeler değil.

## v0.2 paketleri

### Ödeme (`@oyun/ortak/odeme`)

Kurulum, oyun başına bir kez:
1. **Bu depoda göç:** ürün → hak eşlemesi. Örnek: `insert into ortak.urunler values ('halka_paket_tam', 'halka', 'paket_tam');`
2. **RevenueCat:** projeye oyunun uygulamasını (Play/App Store) ekle. Entitlement kimliği = haktaki ad (`paket_tam`), ürün kimliği = mağaza ürün kimliği. RevenueCat'in uygulama kimliklerini (`app_…`, Play ve App Store ayrı) oyunun ayarına yaz: `ayarlar.odeme.revenuecat_uygulamalari = ["app_…"]`. TRANSFER (başka hesapta geri yükleme) yalnız bu eşlemeyle ve yalnız o oyunun haklarını taşır.
3. **RevenueCat → Integrations → Webhooks:**
   - Adres: `https://qzxchutjzhyzzaoxzroh.supabase.co/functions/v1/odeme-webhook`
   - Authorization header: `C:\Users\alise\.oyun-ortak\odeme-webhook.env` dosyasındaki değer. Bütün oyunlar aynı webhook'u kullanır.
4. **Oyunda:** RevenueCat eklentisini `Magaza` arayüzüne saran birkaç satır.

```ts
import { Purchases } from "@revenuecat/purchases-capacitor";
const ent = (c: CustomerInfo) => Object.keys(c.entitlements.active);
const magaza: Magaza = {
  kullaniciAta: async (id) => void (await Purchases.logIn({ appUserID: id })),
  haklar: async () => ent((await Purchases.getCustomerInfo()).customerInfo),
  satinAl: async (urun) => {
    const { products } = await Purchases.getProducts({ productIdentifiers: [urun], type: PRODUCT_CATEGORY.NON_SUBSCRIPTION });
    return ent((await Purchases.purchaseStoreProduct({ product: products[0]! })).customerInfo);
  },
  geriYukle: async () => ent((await Purchases.restorePurchases()).customerInfo),
};
export const odeme = odemeBaslat({ supabase, oyunId, depo, magaza: Capacitor.isNativePlatform() ? magaza : undefined });
```

Kullanım:
- **Açılışta** `await odeme.hakVar("paket_tam")` (önbellekten, ağ beklemez), ardından `odeme.yenile()`.
- **Satın alma:** `odeme.satinAl("halka_paket_tam")`. Web'de `web_satis_yok` hatası verir.
- **Geri yükleme:** `odeme.geriYukle()`.

Davranış:
- **Hak süresizdir:** ağsız açılışta da açık kalır.
- **İade:** RevenueCat iadeyi bildirince sunucuda `iade` olur; bir sonraki `yenile()` hakkı düşürür. Mağaza hâlâ veriyorsa (aile paylaşımı) hak kalır.
- **Web:** hesapta hak varsa görünür, satın alma yapılamaz.
- **Korumalı içerik (HK-8):**
  - Ücretli dosyalar `korumali/<oyun>/<hak>/...` yoluna servis anahtarıyla yüklenir; yükleme betiği oyun deposundadır.
  - Oyun dosyayı `odeme.korumaliIndir("paket_tam", "zor-001.json")` ile alır.
  - Hakkı olmayan hesap indiremez. İnen dosyayı çevrimdışı için saklamak oyunun işidir.

### Etkinlik (`@oyun/ortak/etkinlik`)

- **Takvim:** oyunun Pages sitesinde statik JSON. Örnek: `public/etkinlik/takvim.json` (HK-7, EN-8).
- **Kurulum:** `etkinlikBaslat({ oyunId, adres, depo, dogrula, supabase })`. `dogrula`, ham JSON'dan geçerli takvimi döner ve geçmeyen kayıtları atar (KM-8).
- **Okuma:** `takvim()` ağ yoksa son geçerli takvimi verir. Yardımcılar: `suren(liste)`, `yaklasan(liste)`, `kalanSure(oge)`. Hepsi İstanbul günüyle çalışır, öğelerde `baslangic`/`bitis` (YYYY-MM-DD, dahil) beklenir.
- **Ödül:** `odulKazan("rozet-usta", "usta-2026-11")` cihazda hemen kaydeder; oturum varsa sunucuya bir kez yazar.
- **Eşitleme:** açılışta ve girişten sonra `esitle()`; başka cihazda kazanılanları getirir. Ödül kimliği `^[a-z0-9_:.-]{1,64}$`.
- **Sıralama ödülü (HK-3, "ilk %10"):** `select ortak.siralama_odulu_ver('halka', 'etkinlik', '<etkinlik_id>', 'sira:<odul>', 0.1)`. Oyunun cron işi ya da elle çalıştırılır; eşitler dahil. Kimlik `sira:` ile başlar; bu önekli ödülleri istemci kendine yazamaz.

### Geri bildirim (`@oyun/ortak/geri-bildirim`)

- **Kurulum:** `geriBildirimBaslat({ depo, olcum, anketler, etkin })`. `etkin` kapalı test sürümünde `true` olur; ör. `testKodu(cihaz) != null` ya da derleme bayrağı.
- **Akış:**
  1. Oyun olayları `say("cozum")` ile sayılır.
  2. Uygun anda `siradaki()` anket döner. Oyun anketi kendi arayüzüyle gösterir ve `gosterildi(id)` çağırır.
  3. Cevaplar `cevapla(id, cevaplar)` ile verilir.
- **Koşul:** `{ sayac: { ad: "cozum", esik: 5 } }` ve/veya `{ gun: 7 }` (ilk açılıştan bu yana).
- **Gönderim:** cevaplar PostHog'a `geri_bildirim` olayı olarak gider. Serbest metin 200 karakterde kesilir; kişisel veri istenmez.

### Şikâyet (`hesap.sikayetEt`, v0.3)

- **Kullanım:** `hesap.sikayetEt(ad, "ad" | "hile" | "diger")`. Sıralama ya da lig satırındaki adla çağrılır; oyuncu kimliği istemciye hiç verilmez.
- **Kim şikâyet edebilir:** yalnız kalıcı hesaplar (Google, Apple ya da e-posta), günde en çok 20 şikâyet. Anonim hesaplar şikâyet edemez.
- **Ad şikâyeti:** farklı kalıcı hesaplardan gelen şikâyet sayısı eşiğe ulaşınca hedefin adı sıfırlanır.
  - Eşik oyunun ayarında: `ayarlar.sikayet.ad_esigi`, varsayılan 3.
  - Yalnız o oyunda en az `ayarlar.sikayet.en_az_gun` (varsayılan 2) gündür oynayan kalıcı hesapların şikâyeti sayılır; daha yeni hesapların şikâyeti kaydedilir ama sayılmaz.
  - Yalnız şu anki ada yapılan şikâyetler sayılır; oyuncu adını değiştirirse eski şikâyetler düşer.
  - Misafirken alınan şikâyetler hesap bağlanınca yeni hesaba taşınır.
  - Sıralama adsız oyuncuyu gösterirken oyun "Oyuncu" yazar.
  - Oyuncu hemen yeni ad seçebilir; 30 gün sınırı sıfırlanır.
- **`hile` ve `diger`:** yalnız kaydedilir. İnceleme Supabase panelinden `ortak.sikayetler` tablosuyla yapılır.
- **Arkadaş düellosu (KH-5'in diğer yarısı):** oyuna özgü kaldı; Koz Hesabı kendi şemasında yapar.

### Kendi sunucusu olan oyun (`@oyun/ortak/sunucu-node`, v0.4)

Sticky Ten gibi gerçek zamanlı sunucusu olan oyunlar için (ST-4).

**Jeton doğrulama:**
```ts
const dogrula = jetonDogrulayici({ url: SUPABASE_URL, anahtar: SUPABASE_ANON_KEY });
const oyuncu = await dogrula(jeton);
```
- Dönüş `{ id, anonim, eposta, bitis }` ya da `null`.
- İmza, süre, `aud` ve `role` denetlenir.
- Socket.IO'da `io.use(...)` içinde `soket.handshake.auth.jeton` ile kullanılır.
- Bağlantı açıkken yenilenen jetonu istemci olayla yeniden gönderir.

**Yazma:**
- `servisIstemcisi({ url, servisAnahtari, sema: "sticky" })` servis rolüyle yazar.
- Servis anahtarı yalnız sunucunun ortam değişkenindedir; istemciye gitmez.

**Sticky Ten (`sticky` şeması):**

| Fonksiyon | Yaptığı |
| --- | --- |
| `sticky.oyun_sonu(oyuncular, gun, ciftler)` | Oyun sonucunu tek işlemde yazar: istatistik, rating, rating günlüğü ve ikili sayaç |
| `sticky.siralama(donem)` | `gun` / `hafta` / `ay` / `tum`; herkese açık, kimlik döndürmez |
| `sticky.haftalik_odul()` | Pazartesi 00:01 İstanbul cron'u; `sira:hafta-ilk10:<hafta>` ve `sira:hafta-ilk3:<hafta>` |
| `sticky.takip_et` / `sticky.takibi_birak` / `sticky.takip_ettiklerim` | Takip, en çok 100 |

- Kullanıcı adı `ortak.oyuncular('sticky')`'de tutulur.
- Deluxe `ortak.haklar` (ürün `sticky_deluxe`, hak `deluxe`).

### Bildirim (`@oyun/ortak/bildirim`)

- **Kurulum:** `bildirimBaslat({ yerel, depo })`. `yerel`, oyunun yerel bildirim eklentisini (ör. `@capacitor/local-notifications`) saran üç işlev: `izinIste`, `planla`, `iptal`.
- **Açıp kapatma:** `ayarla({ acik, saat, dakika, baslik, metin })`. Açarken izin ister.
- **Günlük akış:** günün oyunu bitince `oynandi()` bugünkü hatırlatmayı atlar. Açılışta `yenile()` 7 günlük pencereyi kaydırır.
- **Haftalık ek bildirim (v0.5.0):** `ekPlanla([{ zaman, baslik, metin, oynananGundeAtla? }])` yaklaşan olayları verir (turnuva açıldı, lig sonucu); her İstanbul haftasından en erkeni, en çok 4 hafta kurulur. Ayrı anahtar: `ekAyarla(acik)` (açarken izin ister), `ekAcik()`. Kimlikler `ekKimlikTabani` (varsayılan 7200–7203). `oynandi()` ve `yenile()` ek bildirimleri de yeniden kurar. Ortak kural: günde en çok bir hatırlatma + haftada en çok bir ek bildirim; oyunun kuralları `docs/BILDIRIM.md`.
- **Sunucu push (FCM/APNs):** cihaz anahtarları `ortak.bildirim_anahtarlari`'nda (ST-8: `bildirim_anahtari_yaz`, `bildirim_anahtari_sil`; sunucu servis rolüyle okur). Gönderim için Firebase projesi gerekir.

## Sunucu kuralları (oyun şeması göçleri için)

- Oyun şeması adı oyun kimliğidir (`halka`, `sezgi`). Şema `supabase/config.toml` içindeki `api.schemas` listesine ve canlıda panelde "Exposed schemas" listesine eklenir.
- Kullanıcıya bağlı her tablo `references auth.users on delete cascade` taşır ("Hesabımı tamamen sil" buna dayanır).
- Oyun `<sema>.oyuncu_verisini_sil(uuid)` fonksiyonunu sağlar ve adını `ayarlar.hesap.silme_fonksiyonu`'na yazar ("Bu oyundaki verimi sil").
- RLS her tabloda açık. İstemci tabloya değil, `security definer` + `set search_path = ''` RPC'ye gider.
- **Her göç kendi sonunda** `revoke execute on all functions in schema <sema> from public;` içerir. Postgres her fonksiyona PUBLIC yetkisi verir ve şema bazındaki varsayılan yetki bunu geri alamaz. İstemciye açılacak fonksiyon adıyla `grant` edilir.
- Skoru yalnız `dogrula-<oyun>` (servis rolü) yazar. İstemcinin bildirdiği puan kullanılmaz; cevaplı içerik istemciye gönderilmez.
- Cron işleri `<oyun>-` önekiyle adlandırılır.
- **19–20 Kasım kuralları (`_ortak/OGRENILENLER.md` ÖG-22–38, denetim O18–O24):**
  - Cevabı ya da çözümü açan her RPC `ortak.anonim()` ise reddeder.
  - Herkese açık pahalı sorgu `ortak.hiz_siniri` ile sınırlanır. Anahtar girişliye `auth.uid()`, girişsize yalnız `request.headers ->> 'cf-connecting-ip'`, yoksa `'anon'`; `x-forwarded-for` kullanılmaz.
  - RLS politikasında `auth.uid()` yerine `(select auth.uid())`. Kullanıcıya bağlı yabancı anahtara indeks.
  - Oyunun içerik tablosuna açılmış gün koruması (`halka.gecmis_bulmaca_koru` örneği) ve yönetim kaydı tetikleyicisi (`ortak.yonetim_kaydet('<anahtar sütunu>')`).
  - Zamanlanmış iş tekrarlanabilir (`on conflict do nothing`) ve gece yarısı (00:00–00:30 İstanbul) dışında.
  - Büyük tabloda indeks `create index concurrently` ile göçten önce elle.
  - Yayından önce `supabase db advisors --remote <ref> --type all`.

### `ortak.oyunlar.ayarlar`

```jsonc
{
  "ad":       { "en_az": 3, "en_cok": 16, "degistirme_gun": 30, "yasakli": ["koz"], "onekler": ["Çırak", "Kalfa"] },
  "hesap":    { "baglama_odulu": "desen-porselen", "silme_fonksiyonu": "halka.oyuncu_verisini_sil" },
  "siralama": { "yon": "azalan", "esitlik": "ortak", "dagilim_esigi": 50 },
  "lig":      { "kademeler": ["Çırak", "Kalfa", "Usta", "Başusta", "Üstat"], "grup_boyu": 50,
                "cikis_orani": 0.2, "inis_orani": 0.2, "en_iyi_gun": 5, "esitlik": "ortak", "bant_genisligi": 0 }
}
```

Alanların anlamı:

| Alan | Anlamı |
| --- | --- |
| `siralama.yon` | `"artan"`: küçük puan önde (süre gibi) |
| `siralama.esitlik` | `"ikincil"`: eşit puanda `ikincil` küçük olan önde. `"ortak"`: eşitler aynı sırayı paylaşır |
| `lig` | Yazılmazsa oyunun ligi yoktur |
| `lig.bant_genisligi` | `> 0` ise gruplar `seviye_puani`'na göre ayrılır (KH-4) |
| `ad.yasakli` | Oyuna özgü ek yasaklı sözler |
| `ad.onekler` | Artık kullanılmıyor (15 Kasım 2026: otomatik ad `#` + 5 karakter) |

İstek sınırı fonksiyonun içinde verilir: `istek({ oyunId, kullaniciDakika, oyunDakika })`. Kullanıcı sınırı oyunun bütün doğrulama fonksiyonları için ortaktır.

## `dogrula-<oyun>`

- İstek bütçesi (v0.20–0.21): gönderim verisi tek RPC'de (`halka_gonderim_verisi` örneği), hız sınırı `c` bağlamında tek istek (`istek_siniri`), sıra `skorYaz` yanıtından (`c.sira` ayrı istek atmaz).
- Sunucu bayrakları: `ayarlar.bayraklar.kapali` içindeki özelliğin gönderimini 403 `kapali` ile reddet.
- Süre `sunucu/sure.ts` `aktifSureMs` ile; skora `nabizBoslugu` true ise `nabiz_boslugu` bayrağı.

- `sablon/dogrula/index.ts` ve `deno.json` kopyalanır. İçe aktarma etiketli adresten yapılır (`.../oyun-ortak/v0.1.0/sunucu/mod.ts`).
- Gövde sözleşmesi oyunun ISTEKLER satırındakidir (KM-6, EN-1, HK-1).
- Durum tutan oyunlarda yeniden gönderimi tanımak için olay günlüğü durumda tutulur. Eski sırayla gelen olay günlükteki olayla aynıysa "tekrar" sayılır, farklıysa 409 döner.
- Yayın:
  1. Yerel yığında dene.
  2. Oyun deposundan `npx supabase functions deploy dogrula-<oyun> --project-ref <oyun-canli>`.

## Testler

Yeni oyun başlangıçta, geçişten önce `_ortak/OYUN_DENETIMI.md` denetiminden geçer; sonuç oyunun `docs/DENETIM.md` dosyasına kanıtla yazılır. Kuralın belgede yazılı olması uygulandığı anlamına gelmez.

Bu depo:
- `npm test`: istemci, sunucusuz.
- `npm run test:sunucu`: yerel Supabase'e karşı.
- İkisi de yerelde, gönderimden önce koşulur. Oyun depolarında GitHub Actions kullanılmaz (2026-11-14 kararı; gizli depolarda dakika kotası var). Yalnız açık oyun-ortak deposunun `test.yml`'i kalır.

Yeni bir RPC eklendiğinde `tests/sunucu/yetki.test.ts` içindeki izin listesine bilerek eklenir.

Yerelde geliştiren için not: Edge çalıştırıcısı fonksiyon kodunu önbellekte tutar. Kod değişince `docker restart supabase_edge_runtime_oyun-ortak` gerekir.

## Sunucu süresi ve yinelenen teslim (21 Kasım 2026)

`aktifSureMs` teslimde `durdu`yu yok sayar ve `simdi − son_nabiz`'i ekler (bilinçli: duraklatıp bekleyerek süre kısaltılamasın). Sonuç: teslim `ad_gerekli` döner ya da yanıt kaybolur da oyuncu ad seçip teslimi yinelerse aradaki süre de sayılır. Doğrusu: ilk sayılan teslimde süreyi denemenin durumuna yaz (`teslim: { aktifMs, ... }`), yinelenen teslim bu değeri kullansın (Ezber Bozan `dogrula-ezber`, Ense ve Remzle aynı kalıp). Yeni oyunda dogrula yazarken bu satırı denetle; testine "ad_gerekli sonrası yineleme aynı süreyi verir" senaryosu girsin.
