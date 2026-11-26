# Görev: Köy Meclisi'nden İfade Katı'na "Yalancı Tanık" aktarımı (26 Kasım 2026)

Kurucu kararı: Köy Meclisi ayrı oyun olarak silinir. Değerli çekirdeği (yalancıyı sözlerinin tutarlılığından bulmak, çelişkiyi gerekçesiyle göstermek) İfade Katı'na yeni bir mod olarak aktarılır. Köy Meclisi'nin kodu ve belgeleri arşivde: `C:\Projeler\oyunlar\_ortak\arsiv\koy-meclisi-2026-11-26.zip` (`src/solver.ts`, `answer.ts`, `contradiction.ts`, `notebook.ts`, `hints.ts`, `docs/KURAL_SOZLESMESI.md` §5–§9).

Bu belge tasarım yönünü verir. Kural ayrıntısı İfade'nin `docs/KURAL_SOZLESMESI.md`'sine yeni bölüm olarak yazılır (rulesVersion 4). Ölçülmeyen her sayı "varsayım"dır.

## Neden İfade'ye, neden yeni mod

- İfade'nin dünya modeli (kişi × an × oda, hareket kuralı) Köy'ün çemberinden zengin. Köy'ün asıl sorunu kapasiteydi: tek Kurt'ta 6 kaba kalıp vardı, en sık 3'ü %85 tutuyordu. İfade'de yalan, yerleşim bulmacasının üstüne biner; aynı kalıp sorunu oluşmaz (varsayım, ölçülecek).
- Dış rakip Demon Bluff'ın çekirdeği "çemberde yalancı köylü". İfade'deki biçim (zaman çizgisi ve kat planı) ondan ayrışır.
- İfade'de bugün yalan yok: Klasik modda bütün ifadeler doğru (§4), Mazereti Çürüt'te tam bir ifade yanlış (§9). Yalancı Tanık bu ikisinin arasında bir mod olur.

## Aktarılacaklar

| Köy Meclisi | İfade Katı'ndaki karşılığı |
|---|---|
| Köylünün sözü | **Her ifadenin bir söyleyeni olur** (vakadaki kişilerden biri). Bu yalnız bu modda; Klasik ve Mazereti Çürüt değişmez. |
| `k` Kurt, sözleri yanlış (§2, §3) | Vakada **tam `k` yalancı** (`k` görünür; 1, ileri dosyalarda 2). Yalancının **bütün** ifadeleri yanlış, ötekilerin hepsi doğru. |
| Tutarlı dünya ve tekillik (§5) | **Geçerli vaka:** yalancı kümesi ve kişi-an yerleşimi birlikte **tek**. Çözücü her `k` elemanlı küme için yalancının ifadelerini olumsuzlayıp İfade'nin mevcut çözücüsünü koşar (6 kişi, `k`=1 → 6 deneme; `k`=2 → 15). |
| "Meclisi topla" ve işaretleme (§6) | Oyuncu kişileri yerleştirir ve kişi kartında "yalancı" işaretler. Tamamlanma: yerleşim doğru ve yalancı işareti doğru. |
| Yanlış cevabın gerekçesi (§6.1) | Belirlenimli tek gerekçe, yalnız oyuncunun işaretlemesinden: "Bu işaretlemede {ad}'in ifadesi yanlış kalıyor ama {ad}'i doğru sözlü saydın" (ya da tersi). Çözüm söylenmez; İfade'nin üç durumlu geri bildirimiyle uyumlu olmalı (sızıntı yok). |
| Çelişkiyi Göster (§8) ve B1 bağı (§7.1) | **"Birlikte doğru olamaz" aracı:** oyuncu iki ayrı kişinin birer ifadesini seçer. Hiçbir geçerli çizgide ikisi birlikte doğru olamıyorsa onaylanır ve "bu ikisinden biri yalancı" notu düşer. Denetim yalnız seçilen ifadelere bakar, sızıntı yok. İsteğe bağlı; öğreticide bir kez zorunlu. |
| İpucu yolu (§9) | İpucu sırası: önce bir çelişen çift (B1), sonra yerleşimden bir hücre. Tam çözüm ipucu puanı ADIL_PUAN'a göre düşürür. |
| Ölçüm notu (§7.3) | Tek yalancılı vakalar kolay çözülüyordu (%99 tek bağla). Zorluk eğrisi: K1–K2'de `k`=1, kısa çizgi; K4–K5'te `k`=2 ya da yalancının tek ifadesi olan vakalar. |

## Aktarılmayacaklar

- Çember geometrisi, roller (Bekçi, Çoban, Kahveci, Avcı), "Kurt" teması, Kurt İzi Kilimi sanat yönü, 96 köylük içerik ve Köy'ün uygulaması.
- Kanıt defterinin B2/B3 bağları ve Kanıt Zinciri (§8a): İfade'nin arayüz yükünü artırır; ilk sürümde yalnız B1. Oyuncu verisi isterse sonra.
- Eksik İfade (§8b): ilk sürüme alınmaz; yalancı modu tutarsa ayrıca değerlendirilir.

## İfade Katı oturumunun adımları

1. **Kural:** `KURAL_SOZLESMESI.md`'ye "Yalancı Tanık modu" bölümü (rulesVersion 4). Söyleyen alanı, yalancı sayısı, geçerli vaka, tamamlanma, yanlış cevap gerekçesi, "birlikte doğru olamaz" aracı, ipucu. Belirsiz kalan her nokta `ACIK_KONULAR.md`'ye.
2. **Çekirdek:** `Statement`'a isteğe bağlı `soyleyen` alanı (yalnız bu modda dolu), olumsuzlama, liar-set çözücüsü, B1 denetimi, gerekçe seçimi. Mevcut modların testleri aynen geçmeli.
3. **Kapasite ölçümü:** üreticiyle 4 seviye, sonra bir dosyalık kapasite raporu (tekil vaka oranı, kalıp dağılımı, `k`=1 ve 2). Ölçüt: en sık 3 kalıp %50'nin altında. Tutmazsa mod ertelenir; kurucuya rapor.
4. **Arayüz:** kişi kartında "yalancı" işareti, ifade satırında söyleyen adı, "birlikte doğru olamaz" seçimi. `ARAYUZ.md`'ye yeni ekran yok; mevcut ekranlar genişler. Kaydırma yok kuralı geçerli.
5. **İçerik yeri:** vitrin ve paket kararları kurucuda (yeni mod hangi dosyada açılır, ücretsiz kısma kaç vaka). Günlüğe girmesi ayrı kurucu kararı.
6. **Rapor:** her adım sonunda oyun-ortak oturumuna en çok 3 satır.

## Kabul

- Mevcut Klasik, Kayıp Dakika ve Mazereti Çürüt vakaları ve testleri değişmeden geçer (rulesVersion 1–3 kayıtları eski kurallarıyla okunur).
- Yalancı Tanık vakalarının hepsi tekil; çözücü kanıtlı.
- Yanlış cevap gerekçesi ve "birlikte doğru olamaz" denetimi çözümü sızdırmaz (test).
- Kapasite raporu ölçülmüş sayılarla.
