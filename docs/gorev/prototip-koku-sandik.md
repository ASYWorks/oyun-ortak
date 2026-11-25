# Görev: Koku İzi ve Sandık Ustası ön çalışması (25 Kasım)

Kurucu, GPT portföy incelemesinin önerdiği iki prototipi seçti. Her oyun kendi klasöründe, kendi oturumunda çalışır.

## Başlamadan önce

1. `git init`. Depo şimdilik yalnız yerelde kalır. ASYWorks'te gizli depo açılması kurucu onayıyla olur.
2. Çerçeveyi eşitle: `docs/plan/00-ortak-cerceve.md` 22 Kasım tarihli. Bu tarihten sonra `ORTAK_MODUL.md`, `OYUN_DENETIMI.md` (25 Kasım: K1–K10 kabul senaryoları, kural çakışmaları), `PAZAR_OLCUTLERI.md` ve `ARAYUZ_KURALLARI.md` değişti. Şablonu (`_ortak/sablon-on-calisma/00-ortak-cerceve.md`) yeniden kopyala, oyun adını doldur. Dört dosyayla çelişki görürsen dört dosya geçerlidir. Çelişkiyi oyun-ortak oturumuna bildir.
3. `_ortak/OGRENILENLER.md` dosyasını oku.

## Akış

`docs/plan/OTURUM_GOREVI.md` adımlarını sırayla izle. Her adımın sonunda dur ve kurucunun onayını bekle; kurucu telefondan bağlanır. Karar soruları tek tek, seçenekli sorulur, öneri ilk seçenektir.

GPT incelemesinin bulguları plana ek girdi olarak kullanılır:
- `C:/Users/alise/Documents/Codex/2026-11-23/cl/outputs/oyun-altyapisi-inceleme/portfoy-16-koku-izi.md`. Kabul ölçütleri: yem örneğinde en kısa çözüm 9 tur; koku renk dışında nokta ya da dokuyla gösterilir; 1.600 bölüm üretmeden önce 8–12 görevlik kesit yapılır.
- `.../portfoy-35-sandik-ustasi.md`. Kabul ölçütleri: Sıralı Oy örneğinde 6 tek jetonluk hamleden yalnız biri hedefi kazandırır; kural adları "En çok ilk tercih" ve "Yarıdan fazlası"; ilk kesit üç adımlı öğretici.

**Öncelik sırası (kurucu, 25 Kasım):** ortak oyun kuralları bağlayıcıdır: `YENI_OYUN.md`, `OTURUM_GOREVI.md`, 8 × 200 kapasite, `OYUN_DENETIMI.md`, `ADIL_PUAN`/`RATING_KURALI`, `ARAYUZ_KURALLARI.md` ve `PAZAR_OLCUTLERI.md`. GPT önerileri yalnız bu kurallara uyduğu yerde kullanılır: kabul ölçütüne, örnek teste ya da öğretici tasarımına girdi olarak. Bir GPT önerisi ortak kuralla çelişirse ortak kural geçerlidir; çelişki rapora yazılır.

Kurallar: oyunda dil modeli ya da ücretli API çağrısı yok. Ölçülmeyen sayı "varsayım" diye etiketlenir. Görsel üretimi GPT Sol 6.2 kotasını bekler; o zamana kadar maket ve token yeterli.

## Rapor

Her adım sonunda oyun-ortak oturumuna en çok 3 satır yaz.
