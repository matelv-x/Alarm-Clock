#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$(mktemp -d "${TMPDIR:-/tmp}/alarm-clock-uninstall.XXXXXX")"
trap 'find "$TARGET" -depth -delete' EXIT

mkdir -p "$TARGET/classes/StargateMilkyWay" "$TARGET/web/js" "$TARGET/web/retro/js" \
  "$TARGET/web/.stellar-archive-addon/managed/original-nav-pages" \
  "$TARGET/web/.stellar-archive-addon/originals/original-nav-pages"

cat > "$TARGET/web/index.htm" <<'HTML'
<li class="nav-item">
  <a class="nav-link" href="alarm_clock.htm">Alarm Clock</a>
</li>
<li class="nav-item"><a class="nav-link" href="help.htm">Help</a></li>
HTML
cp "$TARGET/web/index.htm" "$TARGET/web/.stellar-archive-addon/managed/original-nav-pages/index.htm"
cp "$TARGET/web/index.htm" "$TARGET/web/.stellar-archive-addon/originals/original-nav-pages/index.htm"
cp "$TARGET/web/index.htm" "$TARGET/web/.stellar-archive-addon/originals/address_book.htm"

cat > "$TARGET/web/retro/js/navigation.js" <<'JS'
<a href="/alarm_clock.htm">Alarm Clock</a>
<a href="/help.htm">Help</a>
JS
cp "$TARGET/web/retro/js/navigation.js" "$TARGET/web/.stellar-archive-addon/managed/retro-navigation.js"
cp "$TARGET/web/retro/js/navigation.js" "$TARGET/web/.stellar-archive-addon/originals/retro-navigation.js"

STARGATE_ADDON_NO_RESTART=1 APP_DIR="$TARGET" "$ROOT/restore.sh"

if grep -R -n -E 'alarm_clock\.htm|>Alarm Clock<' "$TARGET/web"; then
  echo "Alarm Clock navigation survived uninstall" >&2
  exit 1
fi
grep -q 'help.htm' "$TARGET/web/index.htm"
grep -q 'help.htm' "$TARGET/web/retro/js/navigation.js"
echo "Alarm Clock navigation uninstall test: PASS"
