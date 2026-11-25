# Görev: arayüz dalgası 1 kalanı ve dalga 2 (25 Kasım)

Kaynak: `C:/Users/alise/Documents/Codex/2026-11-23/cl/outputs/oyun-altyapisi-inceleme/arayuz-ve-gorsel-iyilestirme-dizini.md` ("İlk yatırım sırası"). Oyununun bölümü:
`arayuz-inceleme-01-planlama.md` (Mahalle, Kapı, Beat Greedy), `arayuz-inceleme-03-kelime-mantik.md` (Halka).

Dalga 1'in Kelime Köprüsü, Sticky Ten, Remzle ve Sahte kısmı bitti. Dalga 3 (görsel pilot) GPT görsel kotası açılınca yapılacak; bu görevde yok.

| Oyun | İş |
|---|---|
| Halka Kelime | Dalga 1: duraklatma ve gezinme düğmelerinde 44×44 CSS px dokunma alanı (komşu çakışmasız). Aktif / sabit / henüz açılamayan halka renge ek olarak kontur ya da desenle ayrılsın. |
| Mahalle Dönüşümü | Dalga 2: parsel ile neden bağlantısı. Sonuç ekranında hangi parselin hangi nedenle tuttuğu ya da tutmadığı görünsün. |
| Kapı Ustası | Dalga 2: seçili pul ve geçerli hedefler açıkça ayrılsın; geçersiz hamleden sonra oyuncu yardımsız ilerleyebilsin. |
| Beat Greedy | Dalga 2: oyuncunun rotası ile açgözlü rota birbirinden ayrışsın (renk dışında çizgi biçimi ya da etiket). |

Kurallar: oyunun CLAUDE.md ve DENETIM.md dosyaları; açık dil (M1); test önce yazılır; 360×640 ve 390×844 ekranda ölçülür; yayın oyunun kendi oturumundan `yayinla.mjs` ile yapılır. Önizleme tasarımı değişirse kurucuya ekran görüntüsü gönderilir.

Kabul: ilk kez oynayan kişi seçimini ve sonucun nedenini gösterebilir. Rapor en çok 5 satır olsun: ne değişti, hangi testler geçti, yayınlandı mı.
