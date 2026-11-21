#!/bin/sh
# Günlük işletim (20 Kasım, kurucu onayı): canlı yedek + canlı sağlık denetimi. Windows zamanlanmış görevi "oyun-ortak gunluk" çalıştırır.
# Kurulum: docs/ISLETIM.md §1. Günlük: ~/.oyun-ortak/yedek/gunluk.log. Sorun olursa ekrana uyarı penceresi (msg) çıkar.
cd "$(dirname "$0")/.."
GUNLUK="$HOME/.oyun-ortak/yedek/gunluk.log"
mkdir -p "$(dirname "$GUNLUK")"
{
  echo "=== $(date -u +%Y-%m-%dT%H:%MZ)"
  sh scripts/yedek.sh canli > "$GUNLUK.yedek" 2>&1 && Y=0 || { Y=$?; tail -n 5 "$GUNLUK.yedek"; }
  rm -f "$GUNLUK.yedek"
  echo "yedek: çıkış $Y"
  node scripts/saglik.ts canli; S=$?
  echo "sağlık: çıkış $S"
} >> "$GUNLUK" 2>&1
if [ "$Y" != 0 ] || [ "$S" != 0 ]; then
  msg.exe "$USERNAME" "oyun-ortak günlük denetim: yedek çıkış $Y, sağlık çıkış $S. Ayrıntı: $GUNLUK" 2>/dev/null || true
fi
# Günlük dosyası şişmesin: son 2000 satır.
tail -n 2000 "$GUNLUK" > "$GUNLUK.tmp" && mv "$GUNLUK.tmp" "$GUNLUK"
