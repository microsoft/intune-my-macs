#!/bin/zsh
# Pre-install wait script for Swift Dialog
# Purpose: Wait (up to 20 minutes) for the Dialog binary to appear before continuing.
# Exits 0 when /usr/local/bin/Dialog exists (file present & executable), else exits 1 after timeout.

TARGET="/usr/local/bin/Dialog"
MAX_MINUTES=20
SLEEP_SECONDS=5

end_epoch=$(( $(date +%s) + (MAX_MINUTES*60) ))

echo "[pre-install] Waiting for $TARGET (timeout ${MAX_MINUTES}m, interval ${SLEEP_SECONDS}s)" >&2

while true; do
  if [ -x "$TARGET" ]; then
    echo "[pre-install] Found executable: $TARGET" >&2
    exit 0
  fi
  now=$(date +%s)
  if [ $now -ge $end_epoch ]; then
    echo "[pre-install] Timeout after ${MAX_MINUTES} minutes waiting for $TARGET" >&2
    exit 1
  fi
  sleep $SLEEP_SECONDS
done

exit 1  # Should never reach here
