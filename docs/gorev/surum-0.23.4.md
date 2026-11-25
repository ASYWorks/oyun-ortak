# Görev: ortak kütüphane v0.23.4'e geçiş (25 Kasım 2026)

Kurucu kararı: her oyun, sıradaki işiyle birlikte geçer. Ayrı oturum açılmaz.

**Ne değişti** (ayrıntı CHANGELOG.md):
- Sıralama: süresi dolmuş anahtarla çevrimdışı gönderilen skor, ağ dönünce o hesapla gider. Önceden 7 gün sonra düşüyordu.
- Hesap: süresi dolan web devri yalnız kendi hesabına "devir başarısız" der.
- `birlestir`: sunucunun `hesap_degisti` reddi `KayitHatasi("hesap_degisti")` olarak gelir.

API değişmedi. `sunucu/` değişmedi, `--islev` gerekmez. v0.23.3'ten eski oyunlar için `surum-0.23.3.md` dosyasındaki notlar da geçerli.

**Adımlar**
1. `package.json`: `"@oyun/ortak": "github:ASYWorks/oyun-ortak#v0.23.4"`.
2. `npm install` (ya da pnpm); kilit dosyası güncellensin.
3. Tip denetimi, testler, derleme. Bir şey kırılırsa dur ve oyun-ortak'a yaz.
4. Asıl işin yayınıyla birlikte yayınla.
