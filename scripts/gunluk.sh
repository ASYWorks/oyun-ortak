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
  # Panel (panel.asyworks.com) son yedeği buradan görür: ~/.oyun-ortak/panel.env'de PANEL_ANAHTAR_CANLI ve SB_ANON_CANLI.
  # Anahtar ekrana ve günlüğe yazılmaz; çağrı başarısızsa yedek başarısız sayılmaz.
  if [ -f "$HOME/.oyun-ortak/panel.env" ]; then
    . "$HOME/.oyun-ortak/panel.env"
    BOYUT=$(du -sb "$(ls -1d "$HOME/.oyun-ortak/yedek/canli"/*/ 2>/dev/null | sort | tail -1)" 2>/dev/null | cut -f1)
    BASARILI=$([ "$Y" = 0 ] && echo true || echo false)
    K=$(curl -s -o /dev/null -w '%{http_code}' -X POST "https://qzxchutjzhyzzaoxzroh.supabase.co/rest/v1/rpc/yedek_kaydet" \
      -H "apikey: $SB_ANON_CANLI" -H "Content-Type: application/json" -H "Content-Profile: ortak" \
      -d "{\"p_anahtar\":\"$PANEL_ANAHTAR_CANLI\",\"p_proje\":\"canli\",\"p_basarili\":$BASARILI,\"p_boyut\":${BOYUT:-0},\"p_not\":\"gunluk.sh\"}")
    echo "panel yedek kaydı: $K"
  fi
  node scripts/saglik.ts canli; S=$?
  echo "sağlık: çıkış $S"
} >> "$GUNLUK" 2>&1
if [ "$Y" != 0 ] || [ "$S" != 0 ]; then
  msg.exe "$USERNAME" "oyun-ortak günlük denetim: yedek çıkış $Y, sağlık çıkış $S. Ayrıntı: $GUNLUK" 2>/dev/null || true
fi
# Günlük dosyası şişmesin: son 2000 satır.
tail -n 2000 "$GUNLUK" > "$GUNLUK.tmp" && mv "$GUNLUK.tmp" "$GUNLUK"
