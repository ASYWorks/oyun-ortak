# Periyodik işler (bütün oyunlar)

Bütün oyunların tekrarlanan işleri oyun-ortak oturumundan yürür; oyun oturumu yalnız oyun işi (yeni içerik, kural değişikliği) için açılır. Canlıya dokunan her adım kurucunun onayıyla. Gizli anahtarlar `~/.oyun-ortak/` içinde; servis anahtarı `supabase projects api-keys` ile alınır, ekrana basılmaz.

Kaynak: 22 Kasım 2026 envanteri (oyunların LIVEOPS, PUAN, CLAUDE.md belgeleri ve betikleri). Bir oyun yeni bir tekrarlanan iş eklerse buraya da yazılır.

## Kendiliğinden çalışanlar (yalnız izlenir)

| İş | Zaman | Nerede | Kaçarsa |
|---|---|---|---|
| Canlı yedek + sağlık | Her gün 11:00 | Windows görevi "oyun-ortak gunluk" → `scripts/gunluk.sh`; kayıt `~/.oyun-ortak/yedek/gunluk.log` | Bilgisayar kapalıysa yedek yok: açılınca `sh scripts/gunluk.sh` |
| Lig kapanışı | Pazartesi 01:00 UTC | pg_cron `ortak-lig-kapat` | `select ortak.lig_kapat();` |
| Halka Usta Turnuvası ödülü | Pazartesi 00:15 UTC | pg_cron `halka-turnuva-odul` (14 gün geriye bakar) | Kendiliğinden yakalar |
| Sticky haftalık ödül | Pazartesi 00:05 UTC | pg_cron `sticky-haftalik-odul` | **Kendiliğinden yakalamaz:** `select sticky.haftalik_odul('<pazartesi>');` |
| Beat Greedy işleri, temizlik, saklama | Dakikalık/saatlik/gece | pg_cron (ISLETIM §4) | `ortak.isletim_durumu` panelde |
| Render bekçisi | 15 dakikada bir | Worker `asyworks-bekci` | Panelde Render trafiği |
| Panel denetimleri | Her açılışta | panel.asyworks.com (siteler, alan adları, kotalar) | — |

## Her Pazar (kurucu bu oturumu açınca)

1. **Yedek günlüğü:** son 7 günde her gün `yedek: çıkış 0` ve `Sorun yok` var mı (`tail ~/.oyun-ortak/yedek/gunluk.log`).
2. **Panel uyarıları:** rozet, alan adları, kotalar, Render trafiği, işler.
3. **Adil puan haftalık ayarı** (`_ortak/ADIL_PUAN.md`): yeni sürüm Pazartesi başlar, Pazar onaylanır.
   - Beat Greedy: `pnpm levelgen kalibre` (sezgi; SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY), `--write` kurucu onayıyla.
   - Halka: PU-3 kalibrasyonu (`halka-kelime/docs/PUAN.md`).
   - Diğerleri: oyunun PUAN/ADIL_PUAN belgesinde haftalık ayar varsa.
4. **Brevo:** `GET /v3/smtp/statistics/reports?days=7`; günde 210'u (%70) geçerse Resend Pro öner.
5. **PostHog:** kurucunun tarayıcı oturumuyla; Halka 18 Kasım sonrası, `hesap_kilidi_zaman` hatası, yeni olaylar (Ense `oyuncu_testi`, Remzle `geri_bildirim`, `katman_acildi`).
6. **Remzle haftalık rapor:** `PG_URL=<canlı> npx tsx scripts/haftalik-rapor.ts` (sifre-burosu; salt okur), md çıktısı Remzle notlarına. İlki 29 Kasım.
7. **Ense haftalık gözden geçirme:** `npm run olcum:rapor` (etkinlik/lig katılımı, ödül akışı, takvim boşluğu).
8. **Sahte Masası haftalık deste partisi:** oyun oturumu 21 deste üretir ve ön incelemeyi yazar (`docs/inceleme/<tarih>.md`); yükleme buradan `node scripts/yukle.mjs` (SAHTE_SUPABASE_URL, SAHTE_SERVICE_KEY), kurucu onayıyla. Oturum kapalıysa parti beklemede kalır; tampon 14 günün altına inmeden açılmalı.
9. **oyun-test'i uyanık tut:** ücretsiz plan 1 hafta boşta kalan projeyi duraklatır; testte herhangi bir sorgu ya da yayın yeter.
10. **Yedeği makine dışına kopyala:** şifreli arşiv, dış disk ya da bulut (henüz kurulmadı; kurucu kararı bekliyor).

## İçerik tamponu (en az 14 gün, hedef 30+)

22 Kasım 2026 canlı durumu:

| Oyun | Son gün | Kalan | Yükleme |
|---|---|---|---|
| Halka (günlük) | 2027-11-30 | ~373 | `npm run daily` + `node scripts/upload_daily.ts` (+ KV: `scripts/kenar_kv.ts`) |
| Beat Greedy | 2027-11-13 | ~356 | `pnpm levelgen upload --from … --days N` (DAILY_SEED_SECRET gerekir) |
| Ense | 2028-02-28 | 463 | `node tools/gunluk-yukle.ts` (ENSE_SUPABASE_URL, ENSE_SERVICE_KEY) |
| Sahte Masası | 2027-04-07 | 136 | `node scripts/yukle.mjs` (haftalık parti) |
| Remzle | 2027-12-26 | 399 | `npx tsx scripts/anahtar-yukle.ts` (REMZLE_* + pepper) |
| Ezber Bozan | 2027-11-20 | 363 | `node tools/gunluk-yukle.ts` (EZBER_SUPABASE_URL, EZBER_SERVICE_KEY) |

Sağlık betiği şimdilik yalnız Halka ve Beat Greedy'yi denetler; diğer dördü panele eklenecek.

## Tarihli işler

| Tarih | İş |
|---|---|
| 29 Kasım 2026 | Remzle ilk haftalık rapor |
| 30 Kasım 2026 | Ezber puan v3 kendiliğinden başlar; Halka etkinliğini izle |
| 1 Aralık 2026 | Halka kış sezonu (takvimde hazır); Halka yayın temizliği YY-1 en geç bu tarih |
| 7 Aralık 2026 | Remzle K1 rotasyonu ve kasa ailesi başlar (içerik canlıda yüklü); ilk gün kontrol |
| 26 Aralık 2026 | Halka yılbaşı etkinliği (takvimde hazır) |
| ~28 Aralık 2026 | Beat Greedy etkinlik takvimi 3 ay ileriye uzatılmalı (şimdi 2027-03-28'e kadar) |
| İlk lig sezonu bitince | Ezber lig inişi (`inis_orani`) için göç |
| Ramazan tarihleri | Halka ve Ense: Diyanet takvimiyle doğrula |
| ~Mayıs 2027 | Beat Greedy günlük içerik yenilemesi (6 ay kala); Halka etkinlik takvimi 2027-05-31'e kadar |
| 2027-09 | Sticky tema haftaları takvimi bitiyor (2027-09-19), yılda 4–6 tema eklenir |
| 6 ay kala (her oyun) | Ense ve Ezber etkinlik/sezon perdeleri en az 6 ay ileride kalmalı |
| Her ay | Render faturası (~7 $), Supabase kullanım |
| Ekim–Kasım 2027 | Alan adı yenilemeleri: Name.com dördü 6–8 Kasım, asyworks.com 13 Kasım (Cloudflare, otomatik) |
