# PostHog'da olayları görme (her oyun için)

Ölçüm paketi olayları PostHog AB bulutuna yollar. Her olayda `oyun_id`, `surum`, `platform` ve `test` özellikleri vardır. Kapalı test bağlantısıyla (`?t=kod`) açılan cihazlarda `test` alanı o kodu taşır. Bu cihazların dışındaki olaylarda alan boştur.

## 1. Olay üret (telefonda, 10 dakika)

1. Oyunu açık testçi bağlantısıyla aç, örneğin `https://halkakelime.com/?t=deneme`. Ayarlarda **Kullanım ölçümü** açık olmalı.
2. Günlüğü başlat ve bitir. Bir seviyeyi başlat, sonra yarıda bırak. Etkinlik alanını aç. Ligde bir bulmaca çöz. Kozmetik bir desen seç. Satın alma penceresini aç, sonra kapat.
3. Uygulamayı arka plana al. Paket kuyruğu o anda gönderir; normalde 30 saniyede bir gönderir.

## 2. Panelde bak (eu.posthog.com)

1. Sol menüde **Data management → Events** ekranını aç. Arama kutusuna olay adlarını tek tek yaz. Her satırda "Last seen" sütunu olayın en son ne zaman geldiğini gösterir.
2. Daha ayrıntılı bakmak için **Activity → Explore** ekranını aç. Filtreye `oyun_id = halka` ve `test = deneme` ekle. Az önce ürettiğin olaylar burada sırayla görünür.
3. Gerçek oyuncuları görmek için aynı filtrede `test` için **is not set** seç.

## Halka'da beklenen olaylar

| Grup | Olaylar |
| --- | --- |
| Çekirdek | `oturum_basla`, `gunluk_basla`, `gunluk_bitir`, `seviye_basla`, `seviye_bitir`, `satin_alma_goster`, `hesap_bagla`, `hata`, `geri_bildirim` |
| Halka'ya özel | `bulmaca_birak` |
| LiveOps (9) | `event_area_open`, `league_joined`, `league_week_end`, `album_card`, `album_reward`, `event_puzzle_solved`, `event_reward`, `tournament_solved`, `cosmetic_equipped` |

Bazı olaylar yalnız belirli anlarda gelir:
- `league_week_end` hafta kapanınca gelir.
- `album_reward` ve `event_reward` ödül kazanılınca gelir.
- `hata` yalnız bir hata olunca gelir.

Bu olayların görünmemesi tek başına bozukluk sayılmaz.

Listede olmayan bir adla gönderilen olay pakette sessizce düşer, panele hiç ulaşmaz.

## Otomatik testler canlı ölçüme olay göndermez

e2e, ekran görüntüsü ve sığma denetimi gibi otomatik koşular `VITE_POSTHOG_KEY` (ya da oyundaki karşılığı) boş derlenir. Paket anahtar boşsa ölçümü kapatır. Anahtarla koşmak zorunluysa test kodu `e2e` verilir (`t-e2e-…`); panelde `test = e2e` ile süzülür.

Neden kural oldu: 17 Kasım 2026'da Halka'nın PostHog verisinin büyük kısmı testlerden geliyordu. 6 günde 4.847 tek oturumluk cihaz vardı ve gerçek oyuncu görünmüyordu.

Kontrol: panelde günlük farklı cihaz sayısı, beklenen oyuncu sayısının çok üstündeyse ilk şüpheli testlerdir.
