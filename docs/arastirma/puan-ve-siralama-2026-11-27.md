# Puan ve sıralama: araştırma ve kurucu kararları (27 Kasım 2026)

Kurucunun soruları: 0–100 ve süre eşitlik bozucu mantıklı mı; hedef süre mantıklı mı; adil sıralama nasıl yapılır, sıralama olmazsa rekabet hissi kaybolur mu; rekabetin ücretsiz, ücretli kısmın rekabet dışı olması doğru mu. Opus araştırması (web, kaynaklı).

## Bulgular (özet)

| Oyun | Süre | Sıralama | Hile |
|---|---|---|---|
| NYT Mini | Asıl ölçü, saat görünür, duraklatılır; ipucu kullanılırsa istatistikten düşer | Yalnız arkadaş tablosu (100 kişi), genel yok | "Genel tabloda hileyi izlemek imkânsız" (NYT) |
| Wordle, Connections | Yok | Sıralama yok; istatistik, seri, paylaşım | Gerek yok |
| Spelling Bee | Yok | Kişisel rütbe (Genius %70) eşik gibi çalışır | Gerek yok |
| Sudoku turnuvası | Görünür çarpan | Haftalık genel | Doğrulanamadı |
| Royal Match | — | 20 kişilik lig, 3 kademe; King's Cup 50 kişi | Doğrulanamadı |
| Candy Royale | — | 100 kişilik eşleşmiş havuz | Doğrulanamadı |
| Lichess | Zamanlı kipler ayrı ve ratingsiz | Racer'da tablo yok | "Tablo olan yerde hile vardır" |
| Duolingo | XP dolaylı | ~30 kişilik haftalık grup, 10 kademe, terfi/düşme | Aykırı XP silinir; satılık XP güçlendiricisi eleştiriliyor |

Kaynaklar: NYT yardım merkezi (Mini), GamesBeat, Wikipedia (Wordle), Beebom (Spelling Bee), sudokuonline.io, Dream Games yardım (Royal League), King topluluk (Candy Royale), PeopleFun (Wordscapes), Chess.com, lichess.org (Racer, Storm), blog.duolingo.com, Android Authority, Freeman ve ark. 2022 (pay-to-win algısı), Supercell.

- Sırayı görünmeyen bir sürenin belirlediği örnek yok; Fable incelemelerindeki bulgu sektörle de çelişiyor.
- Rekabet hissi için genel tablo gerekmiyor; küçük grup ve arkadaş tablosu yetiyor.
- Oyuncu beceri ve zaman farkını kabul ediyor, paranın beceriyi geçmesini kabul etmiyor.

## Kurucu kararları

| Konu | Karar |
|---|---|
| Eşitlik bozucu | Oyun oyun karar (bugünkü durum). Süre eşitlik bozucuysa görünür olmak zorunda (ADIL_PUAN §6) |
| Süre | Cömert bant (önerilen): medyanın ~2 katı hedef, bant içinde süre puanı değiştirmez, aşım en çok −20; hız ödülü kalkar (Halka +20, §1 +10); "hedef altında" işareti |
| Rakip havuzu | 20–30 kişilik haftalık lig (en iyi 5 gün, benzer etkinlik düzeyi, eşitler hep terfi) + arkadaş tablosu; genel tablo yok (önerilen) |
| Ücretli ve rekabet | Bugünkü kural + para tarafsızlığı testi + ücretliye rekabete girmeyen ek arşiv ve alıştırma hakkı |

Kurallar `_ortak/ADIL_PUAN.md` §0; `ORTAK_MODUL.md` ve şablonda lig grubu 20–30.

## Yapılacaklar

- **oyun-ortak:** arkadaş tablosu (yeni: arkadaş ekleme/kod, `siralama.arkadas()`), lig grup boyu 20–30 ve benzer etkinlik eşleşmesi, eşitlerin hepsinin terfisi (RANK) testi, para tarafsızlığı ortak testi, insan üstü süre bayrağı Pazar raporunda.
- **Oyunlar (bir sonraki büyük sürüm; Halka, Sahte, BG önce):** puan sürümünü cömert banda çevirmek ve hız ödülünü kaldırmak, genel günlük tabloyu arkadaş tablosu ve lige çevirmek, ücretliye ek arşiv/alıştırma, bot raporuna tavan yığılması ve hileci oranı.
