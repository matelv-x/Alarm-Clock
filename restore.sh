#!/bin/bash
set -euo pipefail

TARGET="${APP_DIR:-/home/pi/sg1_v4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.last_backup_path"

fail() { echo "ERROR: $1" >&2; exit 1; }

if [ -f "$STATE_FILE" ]; then
  BACKUP="$(cat "$STATE_FILE")"
else
  BACKUP="$(ls -dt /home/pi/sg1_v4_backup_alarm_* 2>/dev/null | head -n 1 || true)"
fi

[ -n "${BACKUP:-}" ] || fail "No backup path found"
[ -d "$BACKUP" ] || fail "Backup folder does not exist: $BACKUP"

echo "Restoring from: $BACKUP"
if [ "${STARGATE_ADDON_NO_RESTART:-0}" != "1" ]; then
  sudo systemctl stop stargate.service || true
fi
rm -rf "$TARGET"
cp -a "$BACKUP" "$TARGET"
if [ "${STARGATE_ADDON_NO_RESTART:-0}" != "1" ]; then
  sudo systemctl start stargate.service
else
  echo "Stargate restart deferred by add-on manager."
fi

echo "=== RESTORE COMPLETE ==="
