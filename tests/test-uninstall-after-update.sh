#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/alarm-clock-update-uninstall.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

TARGET="$TEST_ROOT/sg1_v4"
PACKAGE="$TEST_ROOT/Alarm-Clock"
BACKUP="${TARGET}_backup_alarm_after_update"
mkdir -p "$TARGET/classes/StargateMilkyWay" "$TARGET/web/js" \
  "$TARGET/web/img" "$TARGET/soundfx/alarm" "$PACKAGE"
cp "$ROOT/restore.sh" "$PACKAGE/restore.sh"
chmod +x "$PACKAGE/restore.sh"

# Reproduce the real failure: an update backup already contains Alarm Clock.
for root in "$TARGET" "$BACKUP"; do
  mkdir -p "$root/classes" "$root/web/js" "$root/web/img" "$root/soundfx/alarm"
  printf 'alarm manager\n' > "$root/classes/alarm_clock_manager.py"
  printf 'alarm wormhole\n' > "$root/classes/alarm_clock_wormhole.py"
  printf 'alarm javascript\n' > "$root/web/js/alarm_clock.js"
  printf 'alarm page\n' > "$root/web/alarm_clock.htm"
  printf 'alarm sound\n' > "$root/soundfx/alarm/tone.wav"
done
printf 'owner background before update\n' > "$BACKUP/web/img/background.png"
printf 'alarm background after update\n' > "$TARGET/web/img/background.png"
printf '%s\n' "$BACKUP" > "$PACKAGE/.last_backup_path"

STARGATE_ADDON_NO_RESTART=1 APP_DIR="$TARGET" "$PACKAGE/restore.sh"

for removed in \
  classes/alarm_clock_manager.py \
  classes/alarm_clock_wormhole.py \
  web/js/alarm_clock.js \
  web/alarm_clock.htm \
  soundfx/alarm; do
  [[ ! -e "$TARGET/$removed" ]] || {
    echo "Alarm Clock-owned path survived uninstall: $removed" >&2
    exit 1
  }
done
grep -q 'owner background before update' "$TARGET/web/img/background.png"
[[ ! -e "$PACKAGE/.last_backup_path" ]]

echo "Alarm Clock update/uninstall detection test: PASS"
