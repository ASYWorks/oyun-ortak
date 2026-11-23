# Oyun yayını (oyun oturumları kendisi yapar)

Her oyun oturumu kendi oyununu `scripts/yayinla.mjs` ile yayınlar. Canlıya giden her adım için kurucunun onayı o oturumda alınır. oyun-ortak oturumu her yayını sonradan denetler ("Son kontrol" bölümü).

## Komut

```
node C:/Projeler/oyunlar/_ortak/oyun-ortak/scripts/yayinla.mjs . <commit> [--islev] [--kuru]
```

Oyun klasöründen çalıştırılır; `node_modules` kurulu olmalıdır (`npm ci`).

| Bayrak | Ne yapar |
|---|---|
| (yok) | e2e (oyun-test) → canlı ortamla derleme → paket denetimi → Pages → canlı adreste yeni sürüm doğrulaması |
| `--islev` | Önce `islevler` oyun-test'e yüklenir, `islevE2e` orada koşar, sonra oyun-canli'ya yüklenir; ardından istemci yayını |
| `--kuru` | Derler ve denetler, hiçbir şey yüklemez. Kurucuya sormadan önce bununla dene |

Betik `git archive <commit>` ile temiz kopyadan derler. Yerel `dist`, `.env.local` ve commit'lenmemiş değişiklik pakete girmez (ÖG-49). Bir adım düşerse betik durur. Durduğu yerden sonrası yapılmaz, günlüğe "durdu" yazılır.

## yayin.json (oyun deposunun kökünde, commit'li)

```json
{
  "oyun": "koz",
  "pages": "koz-hesabi",
  "derle": "npx vite build --config app/vite.config.ts --outDir \"{CIKTI}\" --emptyOutDir",
  "ortam": { "VITE_SUPABASE_URL": "{CANLI_URL}", "VITE_SUPABASE_ANON_KEY": "{CANLI_ANON}",
             "VITE_POSTHOG_KEY": "{POSTHOG_KEY}", "VITE_TURNSTILE_SITE_KEY": "{TURNSTILE_SITE_KEY}" },
  "e2e": "npm run -s e2e:istemci",
  "e2eOrtam": { "E2E_SUPABASE_URL": "{TEST_URL}", "E2E_ANON_KEY": "{TEST_ANON}",
                "E2E_SERVICE_KEY": "{TEST_SERVIS}", "E2E_TURNSTILE_SITE_KEY": "{TURNSTILE_SITE_KEY}" },
  "islevler": ["dogrula-koz"],
  "islevE2e": "npm run -s e2e:sunucu",
  "yasakDosya": ["^icerik/.*gunluk"],
  "yasakMetin": [],
  "gerekliMetin": ["phc_"]
}
```

- `derle`: komut temiz kopyada çalışır. Ya `{CIKTI}` klasörüne yazar ya da `"cikti": "dist"` ile çıktı klasörünü bildirir.
- `ortamSil`: derlemede tanımsız olması gereken değişkenler (Ezber'de `EZBER_TEST_KIPI` gibi).
- `adres`: alan adı `https://<pages>.asyworks.com` değilse.
- `supabaseSunucuda: true`: istemci Supabase adresini kendi sunucusundan alıyorsa (Sticky Ten); "canlı adres pakette" denetimi atlanır, test adresi yasağı sürer.
- `baglantilar`: çalışma alanı paketlerinin kendi node_modules klasörleri (ör. `["apps/mobile/node_modules"]`, pnpm monorepo). Temiz kopyada depodaki aynı klasöre bağlanır, çıkışta kaldırılır. Derleyici önbelleği için her yayın kendi geçici klasörünü (TEMP) kullanır.
- `dizinlenebilir: true`: yalnız yayın gününden sonra (noindex denetimini kapatır).
- Yer tutucular: `{CANLI_URL} {CANLI_ANON} {POSTHOG_KEY} {TURNSTILE_SITE_KEY} {TEST_URL} {TEST_ANON} {TEST_SERVIS} {CIKTI} {KAYNAK}`. Anahtarları betik kendisi alır, ekrana yazmaz. Oyun deposuna hiçbir anahtar girmez.

`yasakDosya` ve `yasakMetin` oyunun kendi sızıntı kurallarıdır. Örnekler: cevaplı gün dosyaları (`^icerik/gun-`), günlük kimlikleri (`"gn-[0-9]{3}`), ücretli içerik imleri. Yeni bir sızıntı yolu bulunursa buraya eklenir.

## Ortak denetim (her oyunda)

- `.map` dosyası yok
- `functions/` klasörü yok
- canlı Supabase adresi var, test adresi yok
- servis anahtarı yok
- `_headers` içinde noindex var
- yayın sonrası canlı adres yeni `index.html` betiklerini sunuyor

## Oyun oturumunda kalanlar ve oyun-ortak'ta kalanlar

| Oyun oturumu (yayinla.mjs ile) | oyun-ortak oturumu |
|---|---|
| İstemci yayını (Pages) | Göçler (tek yazar; numara çakışmasın) |
| Kendi `dogrula-<oyun>` işlevi (`--islev`) | Ortak paket ve sürümü |
| | DNS, Google kaynakları, Vercel taşıma ve kapatma |
| | İçerik yükleme betikleri (servis anahtarıyla canlı veriye yazanlar) |
| | Periyodik işler, panel |

## Yayından sonra

Oyun oturumu oyun-ortak oturumuna tek satır yazar: commit, ne değişti, `--islev` kullanıldı mı.

## Son kontrol (oyun-ortak oturumu)

Her yayın `~/.oyun-ortak/yayin-gunlugu.jsonl` dosyasına bir satır yazar: oyun, commit, Pages yayını, paket boyu, sonuç. oyun-ortak oturumu her yeni satır için şunlara bakar:

1. Önceki yayından bu yana commit farkı. Puan, süre, cevap ve misafir yolları; `yayin.json` değişikliği; yasak listesinden çıkarılan desen.
2. Canlı adres açılıyor, konsolda yeni hata yok.
3. Sorun varsa önceki Pages yayınına geri dönülür, oyun oturumuna yazılır.
