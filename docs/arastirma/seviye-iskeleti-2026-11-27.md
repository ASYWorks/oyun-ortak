# Seviye iskeleti: araştırma ve kurucu kararları (27 Kasım 2026)

Kurucu: "Her oyunun yapısı farklı olabilir ama ortak kurallar içinde ortak bir yapı. Oyuncu sıkılmadan zorluğun kademe kademe arttığını hissetmeli ama zorlanmadan oynayabilmeli." Opus araştırması (web, kaynaklı; çoğu ikincil kaynak).

## Bulgular (özet)

| Oyun | Yapı | Not |
|---|---|---|
| Rush Hour / Unblock Me | 4 × 10 (kutu); Beginner, Intermediate, Advanced, Expert | Kolay paketle öğretim |
| Brain It On | 10 pano × 20, ilk 200 ücretsiz | Beşin dördü sonraki beşi açar |
| Candy Crush | bölüm başına 15; Normal / Hard / Super Hard | Yeni öğe bölüm başında; lig, takım, etkinlik |
| Royal Match | 10.000+; 1–38 zor yok, her onluğun 9'u çok zor, 10'u "zafer turu" | ilk 91 seviyede 11 yeni engel; 2–3 öğrenme tahtası; King's Cup, Lightning Rush, Royal League |
| Cut the Rope | kutu başına 25, her kutu yeni mekanik | |
| Flow Free | paket başına 150, tahta boyuyla zorluk | |
| Two Dots | 25'lik paketler; haftalık Treasure Hunt ilerideki mekaniği tattırır | |
| Monument Valley, Baba Is You, Layton | az ve elle yapılmış seviye; dünya ya da bölüm başına yeni kural | |
| NYT Games | günlük + seri + paylaşım + arşiv (abonelik); çoklu oyun tutunmayı artırıyor (yönetici beyanı) | |
| Sudoku.com | sınırsız, 6 zorluk; günlük, turnuva, sezonluk etkinlik | |

- Paket boyu çoğunlukla 10–25; zorluk adı 3–6, en yaygını 4.
- Eğri testere dişi: tepe, sonra nefes (Royal Match analizi, PuzzleDorf, bugnet). Ayar veriyle (SayGames: %50 kayıp ≈ 2 deneme, "kara delik" seviyeler sadık oyuncuyu kaçırır).
- Öğretim: her adımda tek şey (Apple); yeni öğe için 2–3 tanışma seviyesi (Royal Match); kural ihtiyaç anında yeniden gösterilir (Slyway).
- Tutunma ve gelirde en güçlü kanıt: günlük + seri + paylaşım (NYT) ve 5–50 kişilik kısa yarış etkinlikleri (F2P).

Kaynaklar: gamigion.com (Royal Match), blog.say.games, bugnet.io, indiedb.com (PuzzleDorf), developer.apple.com (onboarding for games), unity.com (FTUE), pocketgamer.com, touchtapplay.com, thinkfun.com, flowfree.fandom.com, thenextweb.com, Wikipedia (Wordscapes, Baba Is You, Threes, Mini Metro), techcrunch.com, layton.fandom.com, easybrain.com, beebom.com, pressgazette.co.uk, digiday.com.

## Kurucu kararları (dördü de önerilen seçenek)

| Konu | Karar |
|---|---|
| İçerik hedefi | X = 5–8 sınıf (bağımsız yeni karar/kural sayısı), Y = 60–400 ölçülen kapasite, toplam en az 1.000 (8 × 200 sabit kuralının yerine) |
| Öğretim | Her oyunda 3–5 seviyelik Başlangıç (Beat Greedy modeli; her seviye tek fikir, ilki kaybedilemez) + her yeni kural/öğe için 2–3 tanışma seviyesi + ilk hatada tek satır hatırlatma |
| Bölüm ve eğri | 20 seviyelik bölüm, testere dişi: ilk 3 kolay, 10 tepe / 11 nefes, 19 nefes / 20 kapı; art arda en çok 2 zor; K5'ten sonra en az 2 kademe düşüş; otomatik test |
| Ortak modlar | Günlük, seri sayacı, paylaşım, arşiv, haftalık lig, etkinlik ortak; zamanlı, sonsuz, rahat mod, düello oyuna göre |

Kurallar: `_ortak/OYUN_DENETIMI.md` 3d (Z1–Z9), `ORTAK_MODUL.md` kesin kararlar, şablon (`00-ortak-cerceve`, `OTURUM_GOREVI` Adım 4, `PLAN_SABLONU` §5), `YENI_OYUN.md`. Mevcut oyunlara bir sonraki büyük sürümde; yayına en yakın üçünde (Halka, Sahte, BG) önce.
