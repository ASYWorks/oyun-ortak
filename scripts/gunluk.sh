#!/bin/sh
# Günlük işletim (20 Kasım, kurucu onayı): canlı yedek + canlı sağlık denetimi. Windows zamanlanmış görevi "oyun-ortak gunluk" çalıştırır.
# Kurulum: docs/ISLETIM.md §1. Günlük: ~/.oyun-ortak/yedek/gunluk.log. Sorun olursa ekrana uyarı penceresi (msg) çıkar.
cd "$(dirname "$0")/.."
GUNLUK="$HOME/.oyun-ortak/yedek/gunluk.log"
mkdir -p "$(dirname "$GUNLUK")"
{
  echo "=== $(date -u +%Y-%m-%dT%H:%MZ)"
  # db dump Docker ister (25 Kasım: Docker kapalıyken yedek sessizce düşüyordu). Kapalıysa açılır, en çok 4 dk beklenir,
  # iş bitince yalnız bu betik açtıysa kapatılır (bellek).
  DOCKER_ACTIK=0
  if ! docker info >/dev/null 2>&1; then
    "/c/Program Files/Docker/Docker/Docker Desktop.exe" >/dev/null 2>&1 &
    DOCKER_ACTIK=1
    i=0; until docker info >/dev/null 2>&1 || [ $i -ge 48 ]; do sleep 5; i=$((i+1)); done
    echo "docker: açıldı ($((i*5)) sn)"
  fi
  sh scripts/yedek.sh canli > "$GUNLUK.yedek" 2>&1 && Y=0 || { Y=$?; tail -n 5 "$GUNLUK.yedek"; }
  rm -f "$GUNLUK.yedek"
  echo "yedek: çıkış $Y"
  # Makine dışı şifreli kopya (Google Drive asyworks0, son 7); parola ~/.oyun-ortak/yedek-parola.txt.
  D=0; if [ "$Y" = 0 ]; then sh scripts/disari-yedek.sh > "$GUNLUK.disari" 2>&1 || D=$?; grep -v NOTICE "$GUNLUK.disari" | tail -n 3; rm -f "$GUNLUK.disari"; fi
  echo "dışarı yedek: çıkış $D"
  # Panel (panel.asyworks.com) son yedeği buradan görür: ~/.oyun-ortak/panel.env'de PANEL_ANAHTAR_CANLI ve SB_ANON_CANLI.
  # Anahtar ekrana ve günlüğe yazılmaz; çağrı başarısızsa yedek başarısız sayılmaz.
  if [ -f "$HOME/.oyun-ortak/panel.env" ]; then
    . "$HOME/.oyun-ortak/panel.env"
    # Boyut yalnız bu çalıştırmada tamamlanan, yedek.sh'nin geçerli saydığı son yedekten (hazırlık ya da yarım klasör sayılmaz).
    BOYUT=0
    if [ "$Y" = 0 ] && SON=$(sh scripts/yedek.sh son canli); then BOYUT=$(du -sb "$SON" 2>/dev/null | cut -f1); fi
    BASARILI=$([ "$Y" = 0 ] && echo true || echo false)
    K=$(curl -s -o /dev/null -w '%{http_code}' -X POST "https://qzxchutjzhyzzaoxzroh.supabase.co/rest/v1/rpc/yedek_kaydet" \
      -H "apikey: $SB_ANON_CANLI" -H "Content-Type: application/json" -H "Content-Profile: ortak" \
      -d "{\"p_anahtar\":\"$PANEL_ANAHTAR_CANLI\",\"p_proje\":\"canli\",\"p_basarili\":$BASARILI,\"p_boyut\":${BOYUT:-0},\"p_not\":\"gunluk.sh\"}")
    echo "panel yedek kaydı: $K"
  fi
  node scripts/saglik.ts canli; S=$?
  echo "sağlık: çıkış $S"
  if [ "$DOCKER_ACTIK" = 1 ]; then docker desktop stop >/dev/null 2>&1 || taskkill.exe //IM "Docker Desktop.exe" //F >/dev/null 2>&1; echo "docker: kapatıldı"; fi
} >> "$GUNLUK" 2>&1
if [ "$Y" != 0 ] || [ "$S" != 0 ] || [ "${D:-0}" != 0 ]; then
  msg.exe "$USERNAME" "oyun-ortak günlük denetim: yedek çıkış $Y, dışarı yedek $D, sağlık çıkış $S. Ayrıntı: $GUNLUK" 2>/dev/null || true
fi
# Günlük dosyası şişmesin: son 2000 satır.
tail -n 2000 "$GUNLUK" > "$GUNLUK.tmp" && mv "$GUNLUK.tmp" "$GUNLUK"
