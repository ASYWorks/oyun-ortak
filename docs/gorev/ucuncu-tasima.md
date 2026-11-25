# Görev: El Bitir, Kayan Yük, Kelime Köprüsü taşıması (25 Kasım)

Kurucu kararı: üç oyun paralel taşınır. Taşımada onay beklenmez (bellek `tasima-onaysiz`): önerilenle ilerle, sonunda raporla. Silme, para, ad, fiyat ve kural istisnası yine kurucuya sorulur.

Taşıma = `@oyun/ortak` (v0.23.4), Cloudflare Pages, `<proje>.asyworks.com`, önizleme kuralları. Yöntem: `docs/ENTEGRASYON.md` ve önceki dört taşıma (Koz, İfade, Kapı, Mahalle).

## Önerilen kimlikler

| Klasör | Oyun kimliği | İstek öneki | Adres |
|---|---|---|---|
| el-bitir | `elbitir` | EB- | el-bitir.asyworks.com |
| kayan-yuk | `kayan` | KY- | kayan-yuk.asyworks.com |
| kelime-koprusu | `kopru` | KK- | kelime-koprusu.asyworks.com |

## Birinci tur (oyun oturumu)

1. **Denetim:** `_ortak/OYUN_DENETIMI.md` ile kanıtlı denetim yap, sonucu `docs/DENETIM.md`'ye yaz.
2. **Envanter ve eşleme:** ENTEGRASYON adım 1–2. Paketteki karşılığı olmayan her parça `oyun-ortak/ISTEKLER.md`'ye istek olarak eklenir: şema, günlük tablosu, sunucu doğrulaması.
3. **Sıralama türü:** puan (`ADIL_PUAN.md`), rating (`RATING_KURALI.md`) ya da yok. Belgede yazılı değilse kurucuya seçenekli sor.
4. **Vercel'e hemen noindex** (bütün taşınan oyunlarda kural). Kişisel depoya push yapılmaz.
5. **Portföy önerileri:** `docs/gorev/portfoy-degerlendirme.md` yöntemiyle değerlendir. Bölümler: El Bitir "26" (`portfoy-tur-5-ayrintili-iyilestirmeler.md`), Kayan Yük "06" ve Kelime Köprüsü "19" (`portfoy-iyilestirme-*.md`). Haklı olanları uygula. Kayan #06/2 (deneme ve ana paket kapsamı) taşıma bitince kurucuya sorulur.
6. **İstemci:** `src/altyapi/` katmanını yaz; hesap, sıralama, ölçüm, kayıt ve geri bildirim paketten gelir. Önizleme (`docs/ONIZLEME.md`) ve kabul senaryoları K1–K10 uygulanır.
7. **`yayin.json`:** önceki dört oyundaki örneğe bak.

## Benim yapacaklarım (oyun-ortak)

Göçler (`ortak.oyunlar` satırı, oyun şeması), `dogrula-<oyun>` işlevinin test ve canlıya yüklenmesi, içerik yükleme, Pages projesi ve alan adı, DNS, Google OAuth kökenleri. Göç numarası almadan önce bana yaz, kendin göç yazma.

## Rapor

Her turda en çok 5 satır: ne bitti, hangi istekler eklendi, bende ne bekliyor.
