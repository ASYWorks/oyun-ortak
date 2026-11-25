#!/bin/sh
# Veritabanı yedeği (19 Kasım işletim incelemesi). Ücretsiz planda Supabase yedeği yok (backups list: []).
# Kullanım: sh scripts/yedek.sh canli|test
# Çıktı: ~/.oyun-ortak/yedek/<proje>/<UTC zaman>/ { roller.sql, sema.sql, veri.sql, cron.sql, ozet.txt, .tamam } ve en çok 14 geçerli yedek tutulur.
# Kapsam: bütün şemalar (auth.users ve kimlikler, storage nesne kayıtları, cron işleri dahil). Storage dosyalarının kendisi,
# Edge Function'lar (git), yapılandırma (config.toml, git) ve gizli değerler (~/.oyun-ortak) bu yedekte değildir.
# Parola ~/.oyun-ortak/supabase-parolalar.txt'den okunur, ekrana yazılmaz. Yedek klasörü yalnız kullanıcıya açıktır.
# Döküm (D10, 23 Kasım): önce aynı üst dizinde özel hazırlık dizinine (.hazirlik-<zaman>-<pid>) yazılır, çıktılar doğrulanır, .tamam
# işareti konur ve tek bir aynı-disk yeniden adlandırmasıyla <zaman> adına yayımlanır. Yarıda kalan döküm hiçbir zaman <zaman>
# klasörü olarak görünmez; hazırlık dizini hata çıkışında silinir. Aynı ada yayımlanmış bir yedek varsa üzerine yazılmaz (çıkış 1).
# Geçerli yedek (rotasyon ve "son yedek" için): adı YYYYAAGGTsaatdakikasaniyeZ, gerçek dizin (symlink değil), roller/sema/veri.sql ve
# ozet.txt boş değil, cron.sql gerçek dosya (boş olabilir). .tamam varsa gerçek dosya ve içeriği klasör adı; yoksa (23 Kasım öncesi
# yedekler) işaret aranmaz. Geçersiz ya da tanınmayan girişler sayılmaz, silinmez.
#   sh scripts/yedek.sh son canli|test   → ağsız; son geçerli yedeğin yolunu yazar (yoksa boş, çıkış 1).
set -eu
DESEN='^[0-9]\{8\}T[0-9]\{6\}Z$'
gecerli() { # $1: dizin yolu
  ad=$(basename "$1")
  echo "$ad" | grep -q "$DESEN" || return 1
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  for f in roller.sql sema.sql veri.sql ozet.txt; do [ -f "$1/$f" ] && [ ! -L "$1/$f" ] && [ -s "$1/$f" ] || return 1; done
  # cron.sql gerçek dosya olmalı; boş olabilir (sıfır cron işi).
  [ -f "$1/cron.sql" ] && [ ! -L "$1/cron.sql" ] || return 1
  # .tamam yoksa eski (işaretsiz) yedektir, geçerli; varsa gerçek dosya olmalı ve içeriği klasör adıyla eşleşmeli.
  if [ -e "$1/.tamam" ] || [ -L "$1/.tamam" ]; then
    [ -f "$1/.tamam" ] && [ ! -L "$1/.tamam" ] || return 1
    [ "$(cat "$1/.tamam")" = "$ad" ] || return 1
  fi
  return 0
}
gecerliler() { # $1: kök; geçerli yedek yolları, eskiden yeniye
  for d in "$1"/*; do [ -e "$d" ] || [ -L "$d" ] || continue; gecerli "$d" && echo "$d"; done | sort
}
if [ "${1:-}" = son ]; then
  case "${2:-}" in canli|test) ;; *) echo "kullanım: sh scripts/yedek.sh son canli|test" >&2; exit 2 ;; esac
  S=$(gecerliler "$HOME/.oyun-ortak/yedek/$2" | tail -n 1)
  [ -n "$S" ] || exit 1
  echo "$S"; exit 0
fi
case "${1:-}" in
  canli) REF=qzxchutjzhyzzaoxzroh; ETIKET="oyun-canli" ;;
  test) REF=vbygbyurswjjmiqrhvmo; ETIKET="oyun-test" ;;
  *) echo "kullanım: sh scripts/yedek.sh canli|test" >&2; exit 2 ;;
esac
PAROLA=$(grep "^$ETIKET veritabani parolasi:" "$HOME/.oyun-ortak/supabase-parolalar.txt" | sed 's/^[^:]*: *//')
[ -n "$PAROLA" ] || { echo "parola bulunamadı ($ETIKET)" >&2; exit 1; }
ZAMAN=$(date -u +%Y%m%dT%H%M%SZ)
KOK="$HOME/.oyun-ortak/yedek/$1"
YAYIN="$KOK/$ZAMAN"
mkdir -p "$KOK"
chmod 700 "$HOME/.oyun-ortak/yedek" "$KOK" 2>/dev/null || true
[ ! -e "$YAYIN" ] && [ ! -L "$YAYIN" ] || { echo "aynı adda yedek var, üzerine yazılmaz: $YAYIN" >&2; exit 1; }
HEDEF="$KOK/.hazirlik-$ZAMAN-$$"
mkdir "$HEDEF"   # -p yok: varsa hata (başka çalıştırıcı)
chmod 700 "$HEDEF" 2>/dev/null || true
YAYIMLANDI=0
trap '[ "$YAYIMLANDI" = 1 ] || rm -rf "$HEDEF"' EXIT
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
# Boru hattı yok: sorgu ayrı adımda dosyaya yazılır, başarısızlığı set -e ile durdurur (POSIX sh'de pipefail yok, boru hattı
# soldaki hatayı yutardı). Ayrıştırma da ayrı adım: geçersiz yanıt node'u düşürür. Sıfır cron işi geçerlidir (boş cron.sql).
npx supabase db query --remote="$REF" -f "$HEDEF/.cron_sorgu.sql" --read-only --yes -o json > "$HEDEF/.cron.json" 2>/dev/null
node -e 'const t=require("fs").readFileSync(process.argv[1],"utf8");const i=t.search(/^[[{]/m);if(i<0)process.exit(3);const j=JSON.parse(t.slice(i));const r=Array.isArray(j)?j:j.rows;if(!Array.isArray(r)||r.some(x=>!x||typeof x.s!=="string"||!/^select cron\.schedule\(/.test(x.s)))process.exit(3);process.stdout.write(r.map(x=>x.s).join("\n")+(r.length?"\n":""))' "$HEDEF/.cron.json" > "$HEDEF/cron.sql"
rm -f "$HEDEF/.cron_sorgu.sql" "$HEDEF/.cron.json"
{
  echo "proje: $1 ($REF)  zaman: $ZAMAN"
  echo "cron.sql: $(grep -c 'cron.schedule' "$HEDEF/cron.sql" || true) iş"
  for f in roller sema veri; do echo "$f.sql: $(wc -c < "$HEDEF/$f.sql") bayt, sha256 $(sha256sum "$HEDEF/$f.sql" | cut -c1-16)"; done
  echo "COPY blokları (tablo): $(grep -c '^COPY ' "$HEDEF/veri.sql" || true)"
  grep '^COPY "auth"."users"\|^COPY "ortak"."skorlar"\|^COPY "ortak"."oyuncular"' "$HEDEF/veri.sql" | cut -c1-60 || true
} > "$HEDEF/ozet.txt"
# Zorunlu çıktı doğrulaması: dört dosya boş olmamalı, cron.sql var olmalı (boş olabilir).
for f in roller.sql sema.sql veri.sql ozet.txt; do [ -s "$HEDEF/$f" ] || { echo "doğrulama: $f boş ya da yok" >&2; exit 1; }; done
[ -f "$HEDEF/cron.sql" ] || { echo "doğrulama: cron.sql yok" >&2; exit 1; }
echo "$ZAMAN" > "$HEDEF/.tamam"
chmod 600 "$HEDEF"/* "$HEDEF"/.tamam 2>/dev/null || true
# Yayımlama: aynı dizinde tek yeniden adlandırma. -T: hedef varsa içine taşımaz; -n: var olanın üzerine yazmaz.
# Ardından gerçekten yayımlandığı denetlenir (hazırlık dizini kalmışsa hedef başkasınındır).
[ ! -e "$YAYIN" ] && [ ! -L "$YAYIN" ] || { echo "aynı adda yedek var, üzerine yazılmaz: $YAYIN" >&2; exit 1; }
mv -T -n "$HEDEF" "$YAYIN"
if [ -d "$HEDEF" ] || [ ! -f "$YAYIN/.tamam" ] || [ "$(cat "$YAYIN/.tamam")" != "$ZAMAN" ]; then
  echo "yayımlanamadı (aynı adda yedek var): $YAYIN" >&2; exit 1
fi
YAYIMLANDI=1
# Rotasyon: yalnız geçerli yedekler sayılır ve silinir; en yeni 14 kalır. Hazırlık dizini, symlink, eksik ya da tanınmayan giriş dokunulmaz.
gecerliler "$KOK" | head -n -14 | while IFS= read -r d; do gecerli "$d" && rm -rf -- "$d"; done
cat "$YAYIN/ozet.txt"
