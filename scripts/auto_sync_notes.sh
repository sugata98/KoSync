#!/bin/sh

# Auto-sync wrapper with locking mechanism
# This script is triggered by udev when WiFi connects

LOCKFILE="/tmp/kobo-autosync.lock"
MAIN_SCRIPT="/mnt/onboard/.adds/nm/scripts/90_sync_notes.sh"
LOG="/mnt/onboard/SyncNotes.log"

# Check if lock exists (another sync is running)
if [ -f "$LOCKFILE" ]; then
    printf "---- %s AUTO-SYNC SKIPPED (already running) ----\n" "$(date)" >> "$LOG"
    exit 0
fi

# Create lock file
touch "$LOCKFILE"

# Log auto-trigger
printf "---- %s AUTO-SYNC TRIGGERED (WiFi connected) ----\n" "$(date)" >> "$LOG"

# Run the main sync script in background and remove lock when done
(
    sh "$MAIN_SCRIPT"
    rm -f "$LOCKFILE"
) &

# Detach completely
exit 0


