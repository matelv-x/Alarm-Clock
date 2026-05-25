#!/bin/bash
set -euo pipefail

TARGET="/home/pi/sg1_v4"
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
sudo systemctl stop stargate.service || true
rm -rf "$TARGET"
cp -a "$BACKUP" "$TARGET"
sudo systemctl start stargate.service

echo "=== RESTORE COMPLETE ==="
