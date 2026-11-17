#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEMP="$(mktemp -d)"
TARGET="$TEMP/sg1_v4"
trap 'find "$TEMP" -depth -delete' EXIT

mkdir -p "$TARGET/classes/StargateMilkyWay" "$TARGET/web/retro/js"

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

APP_DIR="$TARGET" ALARM_CLOCK_MODE=2 STARGATE_ADDON_NO_RESTART=1 \
  "$ROOT/install.sh" >/dev/null

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

[[ "$(grep -o "js/alarm_clock.js?v=$token" "$TARGET/web/alarm_clock.htm" | wc -l | tr -d ' ')" = 1 ]]
[[ "$(grep -o "alarm_clock.htm?v=$token" "$TARGET/web/index.htm" | wc -l | tr -d ' ')" = 1 ]]
[[ "$(grep -o "/alarm_clock.htm?v=$token" "$TARGET/web/retro/js/navigation.js" | wc -l | tr -d ' ')" = 1 ]]

printf 'Alarm Clock install cache-busting test: PASS\n'
