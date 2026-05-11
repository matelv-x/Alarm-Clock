#!/bin/bash
set -euo pipefail

TARGET="/home/pi/sg1_v4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.last_backup_path"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="${TARGET}_backup_alarm_${STAMP}"
WORK_DIR="$SCRIPT_DIR/.alarmclock_work"
ZIP_SRC=""
SRC=""

log() { echo; echo "=== $1 ==="; }
fail() { echo "ERROR: $1" >&2; exit 1; }
warn() { echo "WARNING: $1"; }

find_zip() {
  local candidates=(
    "$SCRIPT_DIR/AlarmClock(1).zip"
    "$SCRIPT_DIR/AlarmClock.zip"
    "$SCRIPT_DIR/alarm_ready_files.zip"
  )
  for f in "${candidates[@]}"; do
    if [ -f "$f" ]; then
      ZIP_SRC="$f"
      return 0
    fi
  done
  return 1
}

require_target() {
  [ -d "$TARGET" ] || fail "Target folder not found: $TARGET"
}

cleanup_work() {
  rm -rf "$WORK_DIR"
}
trap cleanup_work EXIT

extract_zip() {
  mkdir -p "$WORK_DIR"
  unzip -o "$ZIP_SRC" -d "$WORK_DIR" -x "__MACOSX/*" >/dev/null

  if [ -d "$WORK_DIR/AlarmClock/sg1_v4" ]; then
    SRC="$WORK_DIR/AlarmClock/sg1_v4"
  elif [ -d "$WORK_DIR/sg1_v4" ]; then
    SRC="$WORK_DIR/sg1_v4"
  else
    fail "Could not find extracted sg1_v4 inside ZIP"
  fi
}

choose_mode() {
  echo "Using ZIP: $ZIP_SRC"
  echo "Choose background mode:"
  echo "1) Kristian-background"
  echo "2) PolkaDot-background"
  echo "3) Custom"
  read -rp "Enter 1, 2 or 3 [default: 1]: " MODE
  MODE="${MODE:-1}"
  case "$MODE" in
    1|2|3) ;;
    *) echo "Invalid choice. Using Kristian-background."; MODE="1" ;;
  esac
}

backup_target() {
  log "Creating backup"
  cp -a "$TARGET" "$BACKUP"
  echo "$BACKUP" > "$STATE_FILE"
  echo "Backup created: $BACKUP"
}

stop_service() {
  log "Stopping Stargate service"
  sudo systemctl stop stargate.service || true
}

start_service() {
  log "Starting Stargate service"
  sudo systemctl start stargate.service
}

prepare_folders() {
  log "Creating missing folders"
  mkdir -p "$TARGET/classes"
  mkdir -p "$TARGET/classes/StargateMilkyWay"
  mkdir -p "$TARGET/soundfx/alarm"
  mkdir -p "$TARGET/web/js"
  mkdir -p "$TARGET/web/img"
}

copy_full_files() {
  log "Copying full files"
  cp -f "$SRC/classes/alarm_clock_manager.py" "$TARGET/classes/"
  cp -f "$SRC/classes/alarm_clock_wormhole.py" "$TARGET/classes/"
  cp -f "$SRC/web/js/alarm_clock.js" "$TARGET/web/js/"
  cp -f "$SRC/soundfx/alarm/"*.wav "$TARGET/soundfx/alarm/"

  case "$MODE" in
    1)
      cp -f "$SRC/web/alarm_clock.htm (Kristian-background).txt" "$TARGET/web/alarm_clock.htm"
      ;;
    2)
      cp -f "$SRC/web/alarm_clock.htm (PolkaDot-background).txt" "$TARGET/web/alarm_clock.htm"
      ;;
    3)
      cp -f "$SRC/web/alarm_clock.htm (Custom).txt" "$TARGET/web/alarm_clock.htm"
      cp -f "$SRC/web/img/background.png" "$TARGET/web/img/"
      ;;
  esac
}

patch_files() {
  log "Patching files in correct places"
  TARGET_ENV="$TARGET" MODE_ENV="$MODE" python3 <<'PY'
from pathlib import Path
import os
import sys
import re

target = Path(os.environ["TARGET_ENV"])
mode = os.environ["MODE_ENV"]

def fail(msg: str):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)

def warn(msg: str):
    print(f"WARNING: {msg}")

def read(path: Path) -> str:
    if not path.exists():
        fail(f"Missing file: {path}")
    return path.read_text(encoding="utf-8", errors="replace")

def write(path: Path, text: str):
    path.write_text(text, encoding="utf-8")

def insert_after(text: str, anchor: str, addition: str, unique_check: str) -> str:
    if unique_check in text:
        return text
    if anchor not in text:
        fail(f"Anchor not found for insert_after: {anchor!r}")
    return text.replace(anchor, anchor + addition, 1)

def insert_before(text: str, anchor: str, addition: str, unique_check: str) -> str:
    if unique_check in text:
        return text
    if anchor not in text:
        fail(f"Anchor not found for insert_before: {anchor!r}")
    return text.replace(anchor, addition + anchor, 1)

def insert_alarm_li_before_help_html(path: Path):
    text = read(path)

    if 'href="alarm_clock.htm"' in text or "href='alarm_clock.htm'" in text:
        return True

    help_patterns = [
        r'([ \t]*)<li class="nav-item">\s*\n([ \t]*)<a class="nav-link" href="help\.htm">Help</a>\s*\n([ \t]*)</li>',
    ]

    for pattern in help_patterns:
        match = re.search(pattern, text, flags=re.MULTILINE)
        if match:
            indent_li = match.group(1)
            indent_a = match.group(2)

            block = (
                f'{indent_li}<li class="nav-item">\n'
                f'{indent_a}<a class="nav-link" href="alarm_clock.htm">Alarm Clock</a>\n'
                f'{indent_li}</li>\n\n'
            )
            start = match.start()
            text = text[:start] + block + text[start:]
            write(path, text)
            return True

    warn(f"Skipping file without matching Help <li> block: {path}")
    return False

def insert_line_menu(path: Path, line_to_insert: str, required: bool = False):
    text = read(path)
    if line_to_insert.strip() in text:
        return True

    help_candidates = [
        'Help</a>', '>Help<', 'href="help.htm"', "href='help.htm'", 'href="/help"', "href='/help'",
        'Help',
    ]
    for anchor in help_candidates:
        idx = text.find(anchor)
        if idx != -1:
            line_start = text.rfind("\n", 0, idx)
            line_start = 0 if line_start == -1 else line_start + 1
            text = text[:line_start] + line_to_insert + text[line_start:]
            write(path, text)
            return True

    if required:
        fail(f"Could not find Help anchor in {path}")
    warn(f"Skipping file without Help anchor: {path}")
    return False

# stargate.py
stargate_py = target / "classes" / "StargateMilkyWay" / "stargate.py"
text = read(stargate_py)
text = insert_after(
    text,
    "from dialing_log import DialingLog\n",
    "from alarm_clock_manager import AlarmClockManager\n",
    "from alarm_clock_manager import AlarmClockManager"
)
text = insert_after(
    text,
    "        self.dialing_log = DialingLog(self)\n",
    "        self.alarm_clock = AlarmClockManager(self)\n",
    "self.alarm_clock = AlarmClockManager(self)"
)
write(stargate_py, text)

# keyboard_manager.py
keyboard_py = target / "classes" / "keyboard_manager.py"
text = read(keyboard_py)
alarm_stop_block = (
    "        # --- ALARM STOP ---\n"
    "        if key == self.center_button_key and hasattr(self.stargate, 'alarm_clock') and self.stargate.alarm_clock.is_active():\n"
    "            self.log.log('Alarm stop requested from DHD center button')\n"
    "            self.stargate.alarm_clock.stop_alarm()\n"
    "            return\n\n"
)
text = insert_before(
    text,
    "        # Center Button\n",
    alarm_stop_block,
    "Alarm stop requested from DHD center button"
)
write(keyboard_py, text)

# web_server.py
web_server_py = target / "classes" / "web_server.py"
text = read(web_server_py)
text = insert_before(
    text,
    '            elif request_path == "/get/config":\n',
    '            elif request_path == "/get/alarm_clock":\n'
    '                data = self.stargate.alarm_clock.get_alarm_data()\n\n'
    '            elif request_path == "/get/alarm_audio_files":\n'
    '                data = {\n'
    '                    "files": self.stargate.alarm_clock.list_audio_files()\n'
    '                }\n\n',
    'elif request_path == "/get/alarm_clock":'
)
text = insert_before(
    text,
    "            elif self.path == '/update/local_stargate_address':\n",
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
    "elif self.path == '/do/test_alarm_clock':"
)
write(web_server_py, text)

# Insert full <li> block before Help in all web/*.htm except alarm_clock.htm
for htm in sorted((target / "web").glob("*.htm")):
    if htm.name == "alarm_clock.htm":
        continue
    insert_alarm_li_before_help_html(htm)

# navigation.js only for modes 2 and 3
if mode in {"2", "3"}:
    nav_js = target / "web" / "retro" / "js" / "navigation.js"
    if nav_js.exists():
        insert_line_menu(nav_js, ' <a href="/alarm_clock.htm">Alarm Clock</a>\n', required=False)
    else:
        warn(f"navigation.js not found, skipping: {nav_js}")
PY
}

sanity_checks() {
  log "Running sanity checks"
  python3 -m py_compile \
    "$TARGET/classes/alarm_clock_manager.py" \
    "$TARGET/classes/alarm_clock_wormhole.py" \
    "$TARGET/classes/keyboard_manager.py" \
    "$TARGET/classes/web_server.py" \
    "$TARGET/classes/StargateMilkyWay/stargate.py"
}

cleanup_after_install() {
  log "Cleaning unnecessary files from /home/pi"

  rm -rf /home/pi/__MACOSX 2>/dev/null || true
  rm -rf /home/pi/alarm_combajn_package 2>/dev/null || true
  rm -f /home/pi/alarm_combajn_package.zip 2>/dev/null || true

  echo "Cleanup done"
}

main() {
  require_target
  find_zip || fail "No source ZIP found next to install.sh"
  echo "Using ZIP: $ZIP_SRC"
  extract_zip
  choose_mode
  backup_target
  stop_service
  prepare_folders
  copy_full_files
  patch_files
  sanity_checks
  start_service
  cleanup_after_install
  log "Install complete"
  echo "Backup stored at:"
  echo "  $BACKUP"
  echo
  echo "To restore:"
  echo "  cd \"$SCRIPT_DIR\" && ./restore.sh"
}

main "$@"