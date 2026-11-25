# Görev: ortak kütüphane v0.23.3'e geçiş (25 Kasım 2026)

Kurucu: "Push et yayınla sormana gerek yok"; push ve yayın oyunun kendi oturumunda. İzin denetimi aktarılan onayı kabul etmezse kurucuya doğrudan sorulur.

**Ne değişti** (v0.22.3 → v0.23.3; ayrıntı CHANGELOG.md):
- D02: skor kuyruğu hesaba bağlı.
- D03: web devri yeniden denenir.
- D09: ölçüm partisi en çok 60 KB.
- MD-24: `birlestir({ kim })` sunucuda da doğrulanır.
- 7 günden eski takılı kayıt kuyruktan düşer.
- KZ-1: `KayitHatasi` (`kod` alanı).

`sunucu/` klasörü değişmedi: işlev sabitlemesi geçerli, `--islev` gerekmez.

**Adımlar**
1. `package.json`: `"@oyun/ortak": "github:ASYWorks/oyun-ortak#v0.23.3"`.
2. `npm install`; kilit dosyası güncellensin.
3. Tip denetimi, testler, derleme. Bir şey kırılırsa dur ve oyun-ortak'a yaz.
4. İsteğe bağlı: `birlestir` hatasını `e instanceof KayitHatasi` ile ayırt et.
5. Commit, push, `node C:/Projeler/oyunlar/_ortak/oyun-ortak/scripts/yayinla.mjs . <commit>`.
6. Rapor en çok 5 satır olsun: commit, yayın kimliği, varsa sorun. Sonuna "kapatılabilir" ekle.
