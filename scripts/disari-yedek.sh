#!/bin/sh
# Makine dışı yedek (Codex işletim önerisi, kurucu 25 Kasım): son geçerli canlı yedek şifrelenip Google Drive'a (asyworks0) gider.
#   sh scripts/disari-yedek.sh            → yükler, son 7'yi tutar
#   sh scripts/disari-yedek.sh dogrula    → son yüklenen kopyayı indirip çözer, özetini yereldekiyle karşılaştırır
# Şifre: rclone crypt (dosya içeriği ve adı). Parola ~/.oyun-ortak/yedek-parola.txt (kurucu yazdı, parola yöneticisinde de var);
# rclone.conf'a yazılmaz, ekrana ve günlüğe yazılmaz. Drive bağlantısı: rclone remote "gdrive" (scope drive.file).
# Not: rclone'un ortak Google client_id'si 2026'da kapanıyor; kendi client_id açılınca `rclone config update gdrive client_id=…`.
set -eu
cd "$(dirname "$0")/.."
RC=${RCLONE:-$(ls "$LOCALAPPDATA"/Microsoft/WinGet/Packages/Rclone.Rclone_*/rclone-*/rclone.exe 2>/dev/null | tail -1)}
[ -n "$RC" ] && [ -x "$RC" ] || { echo "rclone bulunamadı" >&2; exit 1; }
PF="$HOME/.oyun-ortak/yedek-parola.txt"
[ -s "$PF" ] || { echo "parola dosyası yok: $PF" >&2; exit 1; }
# BOM, satır sonu ve sondaki boşluk atılır; parola değişkende kalır, hiçbir yere yazdırılmaz.
PAROLA_OBS=$(sed '1s/^\xEF\xBB\xBF//' "$PF" | head -n 1 | tr -d '\r\n' | "$RC" obscure -)
export RCLONE_CONFIG_GSIFRELI_TYPE=crypt RCLONE_CONFIG_GSIFRELI_REMOTE=gdrive:asyworks-yedek RCLONE_CONFIG_GSIFRELI_PASSWORD="$PAROLA_OBS"
unset PAROLA_OBS
SON=$(sh scripts/yedek.sh son canli) || { echo "geçerli canlı yedek yok" >&2; exit 1; }
AD=$(basename "$SON")
GECICI=$(mktemp -d); trap 'rm -rf "$GECICI"' EXIT

if [ "${1:-}" = dogrula ]; then
  UZAK=$("$RC" lsf gsifreli:canli 2>/dev/null | sort | tail -n 1)
  [ -n "$UZAK" ] || { echo "Drive'da yedek yok" >&2; exit 1; }
  "$RC" copyto "gsifreli:canli/$UZAK" "$GECICI/$UZAK" -q
  mkdir "$GECICI/ac"; tar -xf "$GECICI/$UZAK" -C "$GECICI/ac"
  Y=$(basename "$UZAK" .tar)
  for f in roller.sql sema.sql veri.sql; do
    a=$(sha256sum "$GECICI/ac/$Y/$f" | cut -c1-16); b=$(sha256sum "$HOME/.oyun-ortak/yedek/canli/$Y/$f" 2>/dev/null | cut -c1-16)
    echo "$f: Drive $a, yerel ${b:-yok} $([ "$a" = "$b" ] && echo aynı || echo FARKLI)"
  done
  exit 0
fi

tar -cf "$GECICI/$AD.tar" -C "$(dirname "$SON")" "$AD"
"$RC" copyto "$GECICI/$AD.tar" "gsifreli:canli/$AD.tar" -q
# Son 7 kopya kalır.
"$RC" lsf gsifreli:canli | sort | head -n -7 | while IFS= read -r f; do "$RC" deletefile "gsifreli:canli/$f" -q; done
echo "dışarı yedek: $AD ($(du -k "$GECICI/$AD.tar" | cut -f1) KB), Drive'da $("$RC" lsf gsifreli:canli | wc -l) kopya"
