#!/bin/sh
# Veritabanı yedeği (19 Kasım işletim incelemesi). Ücretsiz planda Supabase yedeği yok (backups list: []).
# Kullanım: sh scripts/yedek.sh canli|test
# Çıktı: ~/.oyun-ortak/yedek/<proje>/<UTC zaman>/ { roller.sql, sema.sql, veri.sql, ozet.txt } ve en çok 14 yedek tutulur.
# Kapsam: bütün şemalar (auth.users ve kimlikler, storage nesne kayıtları, cron işleri dahil). Storage dosyalarının kendisi,
# Edge Function'lar (git), yapılandırma (config.toml, git) ve gizli değerler (~/.oyun-ortak) bu yedekte değildir.
# Parola ~/.oyun-ortak/supabase-parolalar.txt'den okunur, ekrana yazılmaz. Yedek klasörü yalnız kullanıcıya açıktır.
set -eu
case "${1:-}" in
  canli) REF=qzxchutjzhyzzaoxzroh; ETIKET="oyun-canli" ;;
  test) REF=vbygbyurswjjmiqrhvmo; ETIKET="oyun-test" ;;
  *) echo "kullanım: sh scripts/yedek.sh canli|test" >&2; exit 2 ;;
esac
PAROLA=$(grep "^$ETIKET veritabani parolasi:" "$HOME/.oyun-ortak/supabase-parolalar.txt" | sed 's/^[^:]*: *//')
[ -n "$PAROLA" ] || { echo "parola bulunamadı ($ETIKET)" >&2; exit 1; }
ZAMAN=$(date -u +%Y%m%dT%H%M%SZ)
KOK="$HOME/.oyun-ortak/yedek/$1"
HEDEF="$KOK/$ZAMAN"
mkdir -p "$HEDEF"
chmod 700 "$HOME/.oyun-ortak/yedek" "$KOK" "$HEDEF" 2>/dev/null || true
cd "$(dirname "$0")/.."
# CLI döküm sırasında da config.toml'u okur: env(...) değerleri yüklü olmalı (ekrana yazılmaz).
set -a
for f in giris-epostasi resend google turnstile; do [ -f "$HOME/.oyun-ortak/$f.env" ] && . "$HOME/.oyun-ortak/$f.env"; done
set +a
npx supabase db dump --remote="$REF" -p "$PAROLA" --role-only -f "$HEDEF/roller.sql" >/dev/null 2>&1
npx supabase db dump --remote="$REF" -p "$PAROLA" -f "$HEDEF/sema.sql" >/dev/null 2>&1
npx supabase db dump --remote="$REF" -p "$PAROLA" --data-only --use-copy -f "$HEDEF/veri.sql" >/dev/null 2>&1
# pg_cron işleri dökümde yok (geri yükleme denemesinde cron.job 0 satır): yeniden kurulum SQL'i ayrıca alınır.
printf "select format('select cron.schedule(%%L, %%L, %%L);', jobname, schedule, command) as s from cron.job order by jobname;\n" > "$HEDEF/.cron_sorgu.sql"
npx supabase db query --remote="$REF" -f "$HEDEF/.cron_sorgu.sql" --read-only --yes -o json 2>/dev/null \
  | node -e 'const t=require("fs").readFileSync(0,"utf8");const j=JSON.parse(t.slice(t.search(/^[[{]/m)));console.log((Array.isArray(j)?j:j.rows).map(r=>r.s).join("\n"))' > "$HEDEF/cron.sql"
rm -f "$HEDEF/.cron_sorgu.sql"
{
  echo "proje: $1 ($REF)  zaman: $ZAMAN"
  echo "cron.sql: $(grep -c 'cron.schedule' "$HEDEF/cron.sql") iş"
  for f in roller sema veri; do echo "$f.sql: $(wc -c < "$HEDEF/$f.sql") bayt, sha256 $(sha256sum "$HEDEF/$f.sql" | cut -c1-16)"; done
  echo "COPY blokları (tablo): $(grep -c '^COPY ' "$HEDEF/veri.sql")"
  grep '^COPY "auth"."users"\|^COPY "ortak"."skorlar"\|^COPY "ortak"."oyuncular"' "$HEDEF/veri.sql" | cut -c1-60
} > "$HEDEF/ozet.txt"
chmod 600 "$HEDEF"/* 2>/dev/null || true
# En çok 14 yedek
ls -1d "$KOK"/*/ 2>/dev/null | sort | head -n -14 | xargs -r rm -rf
cat "$HEDEF/ozet.txt"
