#!/bin/bash
set -euo pipefail

TARGET="${APP_DIR:-/home/pi/sg1_v4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.last_backup_path"
fail() { echo "ERROR: $1" >&2; exit 1; }

[[ -d "$TARGET/classes" && -d "$TARGET/web" ]] || fail "Invalid SG1_v4 target: $TARGET"
[[ -w "$TARGET" ]] || fail "Target is not writable; run this restore with sudo"

BACKUP=""
if [[ -f "$STATE_FILE" ]]; then BACKUP="$(<"$STATE_FILE")"; fi
if [[ -z "$BACKUP" || ! -d "$BACKUP" ]]; then
  BACKUP="$(ls -dt "${TARGET}"_backup_alarm_* 2>/dev/null | head -n 1 || true)"
fi
if [[ -n "$BACKUP" && -d "$BACKUP" ]]; then
  echo "Using Alarm Clock pre-install backup: $BACKUP"
else
  BACKUP=""
  echo "No Alarm Clock pre-install backup found; removing only add-on-owned files and integration blocks."
fi

restore_owned_path() {
  local rel="$1" source="$BACKUP/$1" destination="$TARGET/$1"
  if [[ -n "$BACKUP" && -e "$source" ]]; then
    rm -rf -- "$destination"
    mkdir -p -- "$(dirname -- "$destination")"
    cp -a -- "$source" "$destination"
  else
    rm -rf -- "$destination"
  fi
}

# Restore or remove only files owned by Alarm Clock.
restore_owned_path classes/alarm_clock_manager.py
restore_owned_path classes/alarm_clock_wormhole.py
restore_owned_path web/js/alarm_clock.js
restore_owned_path web/alarm_clock.htm
restore_owned_path web/img/background.png
restore_owned_path soundfx/alarm

# Remove only Alarm Clock additions from shared files. Later add-ons survive.
TARGET_ENV="$TARGET" python3 <<'PY'
from pathlib import Path
import os
import re

target = Path(os.environ["TARGET_ENV"])

def edit(relative, transform):
    path = target / relative
    edit_path(path, transform)

def edit_path(path, transform):
    if not path.is_file():
        return
    original = path.read_text(encoding="utf-8", errors="replace")
    updated = transform(original)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
        print(f"Cleaned navigation: {path}")

edit("classes/StargateMilkyWay/stargate.py", lambda text: text
     .replace("from alarm_clock_manager import AlarmClockManager\n", "")
     .replace("        self.alarm_clock = AlarmClockManager(self)\n", ""))

alarm_stop = (
    "        # --- ALARM STOP ---\n"
    "        if key == self.center_button_key and hasattr(self.stargate, 'alarm_clock') and self.stargate.alarm_clock.is_active():\n"
    "            self.log.log('Alarm stop requested from DHD center button')\n"
    "            self.stargate.alarm_clock.stop_alarm()\n"
    "            return\n\n"
)
edit("classes/keyboard_manager.py", lambda text: text.replace(alarm_stop, ""))

server_blocks = (
    '            elif request_path == "/get/alarm_clock":\n'
    '                data = self.stargate.alarm_clock.get_alarm_data()\n\n'
    '            elif request_path == "/get/alarm_audio_files":\n'
    '                data = {\n'
    '                    "files": self.stargate.alarm_clock.list_audio_files()\n'
    '                }\n\n',
    '            elif request_path == "/get/alarm_clock_pi_time":\n'
    '                data = self.stargate.alarm_clock.get_pi_time_data()\n\n',
    "            elif self.path == '/do/test_alarm_clock':\n"
    "                data = self.stargate.alarm_clock.test_alarm(data.get('audio_file'))\n\n"
    "            elif self.path == '/do/stop_alarm_clock':\n"
    "                data = self.stargate.alarm_clock.stop_alarm()\n\n"
    "            elif self.path == '/update/alarm_clock':\n"
    "                try:\n"
    "                    alarm_data = self.stargate.alarm_clock.update_alarm(data)\n"
    "                    data = {\n"
    "                        \"success\": True,\n"
    "                        \"message\": \"Alarm clock settings saved.\",\n"
    "                        \"alarm\": alarm_data\n"
    "                    }\n"
    "                except Exception as exc:\n"
    "                    data = {\"success\": False, \"message\": str(exc)}\n\n",
)
def clean_server(text):
    for block in server_blocks:
        text = text.replace(block, "")
    return text
edit("classes/web_server.py", clean_server)

alarm_item = re.compile(
    r'^[ \t]*<li\b[^>]*class=["\'][^"\']*\bnav-item\b[^"\']*["\'][^>]*>\s*'
    r'<a\b(?=[^>]*href=["\']/?alarm_clock\.htm["\'])[^>]*>\s*Alarm Clock\s*</a>\s*'
    r'</li>\s*', re.MULTILINE | re.IGNORECASE,
)
alarm_anchor = re.compile(
    r'^[ \t]*<a\b(?=[^>]*href=["\']/?alarm_clock\.htm["\'])[^>]*>\s*Alarm Clock\s*</a>\s*\n?',
    re.MULTILINE | re.IGNORECASE,
)

html_roots = (
    target / "web",
    target / "web/.stellar-archive-addon/managed/original-nav-pages",
    target / "web/.stellar-archive-addon/originals/original-nav-pages",
)
html_pages = []
for root in html_roots:
    if root.is_dir():
        html_pages.extend(root.glob("*.htm"))
for path in (
    target / "web/.stellar-archive-addon/managed/address_book.htm",
    target / "web/.stellar-archive-addon/originals/address_book.htm",
):
    if path.is_file():
        html_pages.append(path)
for page in html_pages:
    if page.name != "alarm_clock.htm":
        edit_path(page, lambda text: alarm_item.sub("", text))

for navigation in (
    target / "web/retro/js/navigation.js",
    target / "web/.stellar-archive-addon/managed/retro-navigation.js",
    target / "web/.stellar-archive-addon/originals/retro-navigation.js",
):
    edit_path(navigation, lambda text: alarm_anchor.sub("", text))
PY

find "$TARGET/classes" -type d -name '__pycache__' -prune -exec rm -rf -- {} + 2>/dev/null || true
if [[ "${STARGATE_ADDON_NO_RESTART:-0}" = "1" ]]; then
  echo "Alarm Clock removed surgically. Stargate restart deferred by add-on manager."
else
  systemctl restart stargate.service
  echo "Alarm Clock removed surgically and Stargate restarted."
fi
