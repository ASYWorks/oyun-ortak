# Görev: ortak dalga 3 (kurucu panel notları, 26 Kasım 2026)

Bütün oyunlar uygular (oturum bir sonraki işinde, ilk iş olarak). Yeni kural değil, kurucunun panelde yazdığı ortak istekler. Bitince DENETIM'e satır, rapora tek satır.

1. **Çift dokunuşta yakınlaştırma yok (not 12, 17).** iOS Safari'de `user-scalable=no` tek başına yetmez; art arda düğmeye basınca sayfa yakınlaşıyor. Kök CSS'e:
   ```css
   html, body, button, a, input, select, textarea, [role="button"], [role="tab"] { touch-action: manipulation; }
   ```
   Oyun alanı kendi hareketini yönetiyorsa (`touch-action: none` gibi) o kalır. Kontrol: Safari'de (ya da iOS benzetiminde) düğmeye hızlı iki kez dokun, sayfa yakınlaşmamalı. A5 satırına kanıt.
2. **Şapkalı yazım yok (not 11).** Oyuncuya görünen metinlerde â, î, û kullanılmaz (kâğıt → kağıt, dükkân → dükkan, hâlâ → hala ...). Özel ad ve marka adı istisnası kurucuya sorulur. Kontrol: dil dosyaları ve içerikte `grep -n "[âîûÂÎÛ]"` sıfır. M1 satırına kanıt. (Kelime oyunlarında sözlük biçimi ayrı karar: Köprü kurucuya sordu, şapkasız seçildi.)
3. **Sekme ve sayfa geçişinde kaydırma hareketi (not 6).** Oklarla geçilen her sekme, sayfa ya da kart dizisinde parmakla sağa/sola sürükleyerek de geçilir (yatay kaydırma eşiği ~40 px, dikey hareketle karışmaz, `prefers-reduced-motion`'da animasyonsuz). Okların erişilebilir düğmeleri kalır. A-maddesi olarak DENETIM'e.

Kurallar `ARAYUZ_KURALLARI.md` ve `OYUN_DENETIMI.md`'ye işlendi (bu belgeyle aynı gün).
