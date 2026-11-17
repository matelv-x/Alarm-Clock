#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEMP="$(mktemp -d)"
TARGET="$TEMP/sg1_v4"
trap 'find "$TEMP" -depth -delete' EXIT

mkdir -p "$TARGET/classes/StargateMilkyWay" "$TARGET/web/retro/js"
mkdir -p "$TARGET/owner-data" "$TARGET/web/img"
dd if=/dev/zero of="$TARGET/owner-data/unrelated.bin" bs=1048576 count=2 >/dev/null 2>&1
printf 'owner background before Alarm Clock\n' > "$TARGET/web/img/background.png"

cat > "$TARGET/classes/StargateMilkyWay/stargate.py" <<'PY'
from dialing_log import DialingLog

class Stargate:
    def __init__(self):
        self.dialing_log = DialingLog(self)
PY

cat > "$TARGET/classes/keyboard_manager.py" <<'PY'
class KeyboardManager:
    def handle(self, key):
        # Center Button
        return key
PY

cat > "$TARGET/classes/web_server.py" <<'PY'
class WebServer:
    def get(self, request_path):
        if True:
            if False:
                pass
            elif request_path == "/get/config":
                data = {}

    def post(self, data):
        if True:
            if False:
                pass
            elif self.path == '/update/local_stargate_address':
                data = {}
PY

cat > "$TARGET/web/index.htm" <<'HTML'
<nav>
  <li class="nav-item">
    <a class="nav-link" href="help.htm">Help</a>
  </li>
</nav>
HTML
touch "$TARGET/web/help.htm"
cat > "$TARGET/web/retro/js/navigation.js" <<'JS'
<a href="/help.htm">Help</a>
JS

LEGACY_BACKUP="${TARGET}_backup_alarm_20260101_000000"
cp -a "$TARGET" "$LEGACY_BACKUP"
printf 'legacy installed Alarm Clock background\n' > "$TARGET/web/img/background.png"
legacy_backup_count_before="$(find "$(dirname "$TARGET")" -maxdepth 1 -type d -name "$(basename "$TARGET")_backup_alarm_*" | wc -l | tr -d ' ')"

APP_DIR="$TARGET" ALARM_CLOCK_MODE=3 STARGATE_ADDON_NO_RESTART=1 \
  "$ROOT/install.sh" >/dev/null

[[ -f "$TARGET/.alarm-clock-addon/backup-manifest" ]]
[[ -f "$TARGET/.alarm-clock-addon/backup/web/img/background.png" ]]
grep -q '^owner background before Alarm Clock$' "$TARGET/.alarm-clock-addon/backup/web/img/background.png"
[[ ! -e "$TARGET/.alarm-clock-addon/backup/owner-data" ]]
legacy_backup_count_after="$(find "$(dirname "$TARGET")" -maxdepth 1 -type d -name "$(basename "$TARGET")_backup_alarm_*" | wc -l | tr -d ' ')"
if [[ "$legacy_backup_count_after" != "$legacy_backup_count_before" ]]; then
  printf 'installer created another legacy full-tree backup\n' >&2
  exit 1
fi
backup_manifest_hash="$(shasum -a 256 "$TARGET/.alarm-clock-addon/backup-manifest" | awk '{print $1}')"

token="$(python3 - "$TARGET/web/js/alarm_clock.js" <<'PY'
from pathlib import Path
import hashlib
import sys
print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest()[:12])
PY
)"

grep -q "js/alarm_clock.js?v=$token" "$TARGET/web/alarm_clock.htm"
grep -q "href=\"alarm_clock.htm?v=$token\"" "$TARGET/web/index.htm"
grep -q "href=\"/alarm_clock.htm?v=$token\"" "$TARGET/web/retro/js/navigation.js"

APP_DIR="$TARGET" ALARM_CLOCK_MODE=keep STARGATE_ADDON_NO_RESTART=1 \
  "$ROOT/install.sh" >/dev/null

[[ "$(shasum -a 256 "$TARGET/.alarm-clock-addon/backup-manifest" | awk '{print $1}')" = "$backup_manifest_hash" ]]

[[ "$(grep -o "js/alarm_clock.js?v=$token" "$TARGET/web/alarm_clock.htm" | wc -l | tr -d ' ')" = 1 ]]
[[ "$(grep -o "alarm_clock.htm?v=$token" "$TARGET/web/index.htm" | wc -l | tr -d ' ')" = 1 ]]
[[ "$(grep -o "/alarm_clock.htm?v=$token" "$TARGET/web/retro/js/navigation.js" | wc -l | tr -d ' ')" = 1 ]]

STARGATE_ADDON_NO_RESTART=1 APP_DIR="$TARGET" "$ROOT/restore.sh" >/dev/null
grep -q '^owner background before Alarm Clock$' "$TARGET/web/img/background.png"
[[ -f "$TARGET/owner-data/unrelated.bin" ]]
[[ ! -e "$TARGET/.alarm-clock-addon" ]]
[[ ! -e "$TARGET/classes/alarm_clock_manager.py" ]]
[[ ! -e "$TARGET/web/alarm_clock.htm" ]]

printf 'Alarm Clock install cache-busting test: PASS\n'
