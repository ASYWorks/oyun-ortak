# Oyun yayını (oyun oturumları kendisi yapar)

Her oyun oturumu kendi oyununu `scripts/yayinla.mjs` ile yayınlar. Canlıya giden her adım için kurucunun onayı o oturumda alınır. oyun-ortak oturumu her yayını sonradan denetler ("Son kontrol" bölümü).

## Komut

```
node C:/Projeler/oyunlar/_ortak/oyun-ortak/scripts/yayinla.mjs . <commit> [--islev] [--kuru]
```

Oyun klasöründen çalıştırılır. Oyun klasörünün `node_modules`'u kullanılmaz (gerekmez): bağımlılıklar arşivlenen commit'in kilit dosyasından temiz kopyanın içine kurulur (Bulgu 6, 23 Kasım):

| Commit kökünde | Kurulum |
|---|---|
| `package-lock.json` | `npm ci --no-audit --no-fund` |
| `pnpm-lock.yaml` (+ `pnpm-workspace.yaml`) | `corepack pnpm install --frozen-lockfile`; `package.json` `packageManager` alanı kilitli bir sürüm olmalı (ör. `pnpm@12.3.4`) |
| hiçbiri, birden çoğu ya da başka (yarn, bun) | betik kurulumdan önce durur; hiçbir şey yüklenmez |

Kurulum kuru koşuda da yapılır (derleme için gerekir). Başarılı yayından sonra çalışma klasörü yalnız `%TEMP%\oyun-yayin\<oyun>-…` ise silinir.

| Bayrak | Ne yapar |
|---|---|
| (yok) | e2e (oyun-test) → canlı ortamla derleme → paket denetimi → Pages → canlı adreste yeni sürüm doğrulaması |
| `--islev` | Sıra: `islevler` oyun-test'e → `islevE2e` (oyun-test) → istemci e2e → derleme → paket denetimi → `islevler` oyun-canli'ya → Pages → canlı doğrulama. Canlıya hiçbir işlev denetimler bitmeden gitmez |
| `--kuru` | Derler ve denetler, hiçbir şey yüklemez: ne oyun-test'e ne canlıya işlev, ne Pages. `--kuru --islev` yalnız `islevler`in dolu olduğunu denetler; `islevE2e` dağıtılmış test sürümüne dayandığı için atlanır (ekranda yazar). Kurucuya sormadan önce bununla dene |

Betik `git archive <commit>` ile temiz kopyadan derler. Yerel `dist`, `.env.local` ve commit'lenmemiş değişiklik pakete girmez (ÖG-49). Bir adım düşerse betik durur. Durduğu yerden sonrası yapılmaz, günlüğe "durdu" yazılır.

Yayın kanıtı (günlük satırında): `commit` (kısa, eski alan) ve `commitTam` (tam oyun commit'i); `paket.sha256` denetlenen paketin
belirlenimci özeti (dosyaların göreli yol sırasıyla `yol\0sha256(içerik)\n` satırlarının SHA-256'sı; klasör adı ve zamandan
bağımsız). `canliKanit`: canlı doğrulamanın neye baktığı. Yerel index.html'deki yerel `.js` betikleri (Vite `/assets/`, Next
`/_next/static/`, Ezber `ana-<özet>.js`, sorgulu `app.js?v=`) canlı sayfada aranır; harici betikler kanıt sayılmaz. Hiç yerel
betik yoksa canlı HTML yerel index.html ile aynı olmalı; boş liste başarı sayılmaz.

Günlük satırı yarım kalan işlemi gösterir: `islevYuklenen: { test: [...], canli: [...] }` o ana kadar başarıyla yüklenen işlevler, `pagesYayin` Pages dağıtım kimliği. Canlı doğrulama geçmezse satır `yayinda-dogrulanamadi` olur ve betik **çıkış 1** ile biter; başarı yalnız `yayinda` + çıkış 0. Geri alma kendiliğinden yapılmaz; oyun-ortak oturumu günlüğe bakıp karar verir.

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
- **ortak-sunucu adresi** (`supabase/functions/*/deno.json`): raw.githubusercontent adresi sürüm etiketinin **commit kimliğiyle** sabitlenir (`git rev-parse v0.x.y^{commit}`), etiketle değil: etiket taşınırsa sonraki --islev incelenmemiş kodu alır (Koz 23 Kasım). Denetimin sunucu_surum sütunu ikisini de kabul eder; etiketli oyunlar sonraki --islev yayınında commit'e geçer.
- `sunucusuz: true`: oyunun arka ucu yok (Hop Koala); "canlı adres pakette" denetimi atlanır.
- `baglantilar` (eski): artık kullanılmaz, varsa yok sayılır ve ekrana yazılır; çalışma alanı paketlerinin `node_modules`'u kurulumla gelir.
- Derleyici önbelleği için her yayın kendi geçici klasörünü (TEMP) kullanır.
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
