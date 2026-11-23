# Periyodik işler (bütün oyunlar)

Bütün oyunların tekrarlanan işleri oyun-ortak oturumundan yürür; oyun oturumu yalnız oyun işi (yeni içerik, kural değişikliği) için açılır. Canlıya dokunan her adım kurucunun onayıyla. Gizli anahtarlar `~/.oyun-ortak/` içinde; servis anahtarı `supabase projects api-keys` ile alınır, ekrana basılmaz.

Kaynak: 22 Kasım 2026 envanteri (oyunların LIVEOPS, PUAN, CLAUDE.md belgeleri ve betikleri). Bir oyun yeni bir tekrarlanan iş eklerse buraya da yazılır.

## Kendiliğinden çalışanlar (yalnız izlenir)

| İş | Zaman | Nerede | Kaçarsa |
|---|---|---|---|
| Canlı yedek + sağlık | Her gün 11:00 | Windows görevi "oyun-ortak gunluk" → `scripts/gunluk.sh`; kayıt `~/.oyun-ortak/yedek/gunluk.log` | Bilgisayar kapalıysa yedek yok: açılınca `sh scripts/gunluk.sh` |
| Lig kapanışı | Pazartesi 01:00 UTC | pg_cron `ortak-lig-kapat` | `select ortak.lig_kapat();` |
| Halka Usta Turnuvası ödülü | Pazartesi 00:15 UTC | pg_cron `halka-turnuva-odul` (14 gün geriye bakar) | Kendiliğinden yakalar |
| Sticky haftalık ödül | Her gün 00:05 UTC (göç 8160) | pg_cron `sticky-haftalik-odul`, geçen hafta verildiyse çıkar | Ertesi gün kendiliğinden yakalar; elle: `select sticky.haftalik_odul('<pazartesi>');` |
| Beat Greedy işleri, temizlik, saklama | Dakikalık/saatlik/gece | pg_cron (ISLETIM §4) | `ortak.isletim_durumu` panelde |
| Render bekçisi | 15 dakikada bir | Worker `asyworks-bekci` | Panelde Render trafiği |
| Panel denetimleri | Her açılışta | panel.asyworks.com (siteler, alan adları, kotalar) | — |

## Her Pazar (kurucu bu oturumu açınca)

1. **Yedek günlüğü:** son 7 günde her gün `yedek: çıkış 0` ve `Sorun yok` var mı (`tail ~/.oyun-ortak/yedek/gunluk.log`).
2. **Panel uyarıları:** rozet, alan adları, kotalar, Render trafiği, işler.
3. **Adil puan haftalık ayarı** (`_ortak/ADIL_PUAN.md`): yeni sürüm Pazartesi başlar, Pazar onaylanır.
   - Beat Greedy: `pnpm levelgen kalibre` (sezgi; SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY), `--write` kurucu onayıyla.
   - Halka: PU-3, servis rolüyle `select * from ortak.kalibrasyon('halka', '<geçen pazartesi>', '<bu pazartesi>');` (ilk dönem 2026-11-23 → 2026-11-30), çıktı CSV olarak halka-kelime/scripts/puan/cikti/kalibrasyon_<bu pazartesi>.csv; ayarı Halka oturumu yapar (docs/PUAN.md §5), yeni sürüm Pazartesi, dogrula-halka yeniden yayını buradan.
   - Diğerleri: oyunun PUAN/ADIL_PUAN belgesinde haftalık ayar varsa.
4. **Brevo:** `GET /v3/smtp/statistics/reports?days=7`; günde 210'u (%70) geçerse Resend Pro öner.
5. **PostHog:** kurucunun tarayıcı oturumuyla; Halka 18 Kasım sonrası, `hesap_kilidi_zaman` hatası, yeni olaylar (Ense `oyuncu_testi`; Remzle `geri_bildirim`, `katman_acildi`, `katman_yanlis`, `sayfa_gecis` {sayfa}, `gunluk_basla.ekran` "GxY", `oyun_oy` (16 sınama oyununda Beğendim/Beğenmedim); Remzle Deneme Dosyası olay göndermez, misafir hunisi için `#deneme` sayfa görüntülemesi).
6. **Remzle haftalık rapor:** `PG_URL=<canlı> npx tsx scripts/haftalik-rapor.ts --cikti C:\Projeler\oyunlar\sifre-burosu\docs\rapor\<YYYY-AA-GG>.md` (sifre-burosu; salt okur). Commit edilmez, Remzle oturumu açılınca okur ve commit eder. "## Alarmlar" bölümünde madde varsa kurucuya ayrıca bir satırla bildirilir; hücre <30 iken alarm çıkmaz. İlki 29 Kasım.
7. **Ense haftalık:** `npm run tampon` (havuz ve etkinlik takvimi kaç gün yetiyor, 6 ayın altında uyarır) ve `npm run olcum:rapor -- olaylar.csv [gün=30]` (D1/D7 tutma, kayıp kaynağı, terk noktaları; JSONL de okur, Ense b527c07'den itibaren). Dosya: kurucu PostHog'a tarayıcıyla girer, SQL `select event, distinct_id, timestamp, properties from events where timestamp > now() - interval 30 day` çalıştırır, CSV indirir (kişisel API anahtarı gerekmez).
8. **Sahte Masası haftalık deste partisi:** oyun oturumu 21 deste üretir ve ön incelemeyi yazar (`docs/inceleme/parti-NN-MM.md`); yükleme buradan `node scripts/yukle.mjs` (SAHTE_SUPABASE_URL, SAHTE_SERVICE_KEY ya da ~/.oyun-ortak/sahte.env), kurucu onayıyla. Partiyle birlikte çoğu zaman Pages yayını da gerekir (kurum defteri, kurallar); istek bunu belirtir. 14 gün uyarısı `node scripts/acilmis.mjs`. Oturum kapalıysa parti beklemede kalır; tampon 14 günün altına inmeden açılmalı.
8b. **Ezber haftalık (elle, PostHog):** İlk Perde hunisi (`perde_basla`/`perde_sonuc`, IP-1…IP-5), takılma (`perde_sonuc` kazandi=false en yüksek sınıf perdeleri, ilk 10), günlük perde deneme dağılımı, misafirden hesaba (`hesap_acildi`), terk (`terk` tur dağılımı). Lig açma ölçütü: son 7 günde ezber günlük sıralamasına giren benzersiz kalıcı hesap sayısı (`ortak.skorlar`); iki hafta üst üste 20'yi geçerse kurucuya sor (onaylanırsa oyun-ortak `ortak.oyunlar` ezber `ayarlar.bayraklar.kapali`'dan "lig"i çıkarır; oyun sürümü gerekmez, kademeli açılış).
8c. **Kapı Ustası haftalık (PostHog):** `kapi-ustasi/docs/OLCUM.md` "Aşama 0 eşikleri" sorguları (D1/D7, ilk oturumda 10 cevap, fiyat ilgisi, mod bazında ilk deneme, anket). İlk koşuda yazım hatası çıkarsa Kapı oturumuna iletilir. Eşikler: D1 ≥ %30, D7 ≥ %10, ilk oturumda 10 görev ≥ %50, fiyat ilgisi ≥ %8.
8d. **Mahalle lig açma ölçütü:** servis rolüyle `select count(*) from (select kullanici_id from ortak.skorlar where oyun_id = 'mahalle' and tur = 'gunluk' and donem::date >= current_date - 7 group by kullanici_id having count(*) >= 3) x;` 300'ü geçerse kurucuya sor; onaylanırsa `ortak.oyunlar` mahalle `ayarlar.bayraklar.lig_acik = true` (uygulama güncellemesi gerekmez; göç 8270).
8e. **Ortak kuralları güncelle (kurucu 22 Kasım):** haftanın kararlarını (kurucunun yeni kuralları, oyunlardan gelen ÖG ve ISTEKLER) _ortak/ORTAK_MODUL.md, OYUN_DENETIMI.md ve sablon-on-calisma şablonlarına işle; şablon sürümünü artır, plan aşamasındaki oyun klasörlerine 00-ortak-cerceve.md'yi yeniden kopyala; FIKIR_KURALLARI.md portföy listesini güncelle.
8f. **Ortak yapı denetimi:** `node scripts/ortak-yapi-denetim.mjs --canli`; ✗ olan oyuna eksiğini yaz (depo, paket sürümü, yayin.json, sunucu önizleme denetimi, önizleme ve testçi, misafir bayrakları, yayın tarihi, yayın günü belgesi, korumalı içerik, canlı yayin ayarı).
9. **oyun-test'i uyanık tut:** ücretsiz plan 1 hafta boşta kalan projeyi duraklatır; testte herhangi bir sorgu ya da yayın yeter.
10. **Yedeği makine dışına kopyala:** şifreli arşiv, dış disk ya da bulut (henüz kurulmadı; kurucu kararı bekliyor).

## İçerik tamponu (en az 14 gün, hedef 30+)

22 Kasım 2026 canlı durumu:

| Oyun | Son gün | Kalan | Yükleme |
|---|---|---|---|
| Halka (günlük) | 2027-11-30 | ~373 | `npm run daily` + `node scripts/upload_daily.ts` (+ KV: `scripts/kenar_kv.ts`) |
| Beat Greedy | 2027-11-13 | ~356 | `pnpm levelgen upload --from … --days N` (DAILY_SEED_SECRET gerekir) |
| Ense | 2028-02-28 | 463 | `node tools/gunluk-yukle.ts` (ENSE_SUPABASE_URL, ENSE_SERVICE_KEY). Ense kuralı L-4: 183 gün kala yeni yıl üretilir (~2027-08-29). Havuz yeniden üretilip yüklenince `node tools/gunluk-referans.ts` + Pages yayını (ölçü puanları) |
| Sahte Masası | 2027-05-19 | 178 | `node scripts/yukle.mjs` (haftalık parti; oyun oturumunda "Haftalık parti" komutu) |
| Remzle | 2027-12-26 | 399 | `npx tsx scripts/anahtar-yukle.ts` (REMZLE_* + pepper) |
| Ezber Bozan | 2027-11-20 | 363 | `node tools/gunluk-yukle.ts` (EZBER_SUPABASE_URL, EZBER_SERVICE_KEY) |

Sağlık betiği şimdilik yalnız Halka ve Beat Greedy'yi denetler; diğer dördü panele eklenecek.

## Tarihli işler

| Tarih | İş |
|---|---|
| 29 Kasım 2026 | Remzle ilk haftalık rapor. (BG submit_attempt 22 Kasım yayınlandı, v3 hazır) |
| 23 Kasım 2026 | Koz albüm sezonu 2027-1 başlar (görseller yer tutucuyla). (Kapı yayını 22 Kasım akşamı kurucu onayıyla yapıldı, Kapı önizlemede.) |
| 30 Kasım 2026 | Beat Greedy puan v3 başlar: o günün ilk Keşif tesliminde skor ayrıntısında formul 3 olmalı. Halka ilk gerçek etkinlik (hafta-2026-11-30): dogrula-halka 409/422 ve basla pencere 409 (30 Kasım'da sıfıra inmeli), halka.etkinlik_cozumler, ortak.oduller'de rozet-etkinlik-hafta-2026-11-30 ilk kez 5. çözümde ve yalnız kaynak='sunucu' (değilse odul_kaydet delinmiş), halka_turnuva_dosya('hafta-2026-11-30-1') 29 Kasım null / 30 Kasım dolu, bilet exp 2026-12-06T21:00Z, kenar 503 ~0. ~~Gündüz yy1-halka.ts kuru koşu~~ (YY-1 yayınla birlikte ertelendi) (etkinlik çözümlerine ve rozetlere dokunmadığını doğrula), gece kurucu onayıyla uygula (Halka yayını 1 Aralık, src/presets.ts LAUNCH). Ezber puan v3 kendiliğinden başlar: ilk teslimlerde döküm "deneme" kalemini taşır, `ikincil` = deneme × 3600 + saniye, hız ödülü kalemi yok; kayıp ya da baştan başlatma `yeniden` çağırır. Sorunda geri dönüş `puan/puan.ts` SURUM_BASLANGIC (oyun oturumu). Halka etkinliğini izle |
| ~~1 Aralık 2026~~ | Halka yayını **ertelendi** (kurucu 22 Kasım: Halka da önizleme planına uyar, tarih sarkabilir; docs/ONIZLEME.md). Yayın tarihi belli olunca ayarlar.yayin_tarihi, takvim kaydırma, YY-1 (yy1-halka.ts) ve yayin-temizligi.ts o güne göre. Kış sezonu ve yılbaşı etkinliği takvimi de yayın tarihine göre yeniden bağlanır |
| 7 Aralık 2026 | Remzle K1 rotasyonu ve kasa ailesi başlar (içerik canlıda yüklü). Kontrol: (a) sifre-burosu'da `npm run preview -- 2026-12-07` K1 motorunu ve K3 kural metnini yazdırır, canlıyla aynı olmalı; (b) gün içinde PostHog'da o günün `katman_acildi`/`katman_yanlis` oranı önceki 7 günle kıyas, K1'de belirgin artış varsa kurucuya bildir. Yeni K1 motorları (Polybius, Tuş Takımı, Afin, Klavye, İkili Kod, Domuz Ağılı) ilk iki hafta haftalık raporun "Motor bazında" tablosundan izlenir |
| 21 Aralık 2026 | Halka yılbaşı etkinliği 21 Aralık – 3 Ocak (takvimde hazır) |
| 7 Ocak 2027 | hopkoala.com'un Name.com aktarım kilidi biter; Cloudflare Registrar'a taşınabilir (Hop Koala) |
| ~28 Aralık 2026 | Beat Greedy etkinlik takvimi 3 ay ileriye uzatılmalı (şimdi 2027-03-28'e kadar) |
| İlk lig sezonu bitince | Ezber lig inişi (`inis_orani`) için göç |
| Ramazan tarihleri | Halka ramazan-2027 1–14 Mart (bayramı kapsar); Halka ve Ense: Diyanet takvimiyle doğrula. Ense etkinlikleri: Ramazan 2027 6–8 Mart, Kurban 2027 13–15 Mayıs, Ramazan 2028 23–25 Şubat (tahmin) |
| ~27 Ağustos 2027 | Ense etkinlik ve sezon takvimi uzatılmalı (şimdi 2028-02-27'ye kadar); ~29 Ağustos Ense günlük havuzunun yeni yılı (L-4) |
| ~Mayıs 2027 | Beat Greedy günlük içerik yenilemesi (6 ay kala); Ezber günlük havuzunun yeni yılı: önce oyun oturumunda üretim (`uret`, `sec`, `npm run gunluk`, `dogrula`; kimlik EB-G-366'dan devam), sonra buradan `gunluk-yukle` |
| Kurucu tarih verince | Ezber albüm 1. sezon takvimi (oyun oturumu); 23 albüm görseli (`art/paket_4`) GPT kotası açılınca |
| ~Ekim 2027 | Halka etkinlik takvimi ve günlükler yeni yıl: node scripts/generate_events.ts, sonra upload_daily ve KV (takvim 2027-12-05'e kadar) |
| 2027-09 | Sticky tema haftaları takvimi bitiyor (2027-09-19), yılda 4–6 tema eklenir |
| 6 ay kala (her oyun) | Ense ve Ezber etkinlik/sezon perdeleri en az 6 ay ileride kalmalı |
| Her ay | Render faturası (~7 $), Supabase kullanım |
| Ekim–Kasım 2027 | Alan adı yenilemeleri: Name.com dördü 6–8 Kasım, asyworks.com 13 Kasım (Cloudflare, otomatik) |
