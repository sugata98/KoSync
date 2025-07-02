#!/bin/sh

# Paths
RCLONE=/mnt/onboard/.adds/nm/bin/rclone
SQLITE=/mnt/onboard/.kobo/KoboReader.sqlite
WGET=/usr/bin/wget

# Logging & config
LOG=/mnt/onboard/SyncNotes.log
CONF=/mnt/onboard/.config/rclone/rclone.conf
SRC=/mnt/onboard/.kobo
DEST=b2:KoboSync/kobo

# Performance tuning flags
RCOPY_FAST_FLAGS="--fast-list --transfers 8 --checkers 4"

# Telegram
BOT_TOKEN="7702993686:AAF5l8wQwcqYRn2TifnuseJTk9SZISm49Xw"
CHAT_ID="747709506"

printf "---- %s START SYNC ----\n" "$(date)" >> "$LOG"
START_TS=$(date +%s)

# 1) Merge WAL into main DB
/mnt/onboard/.adds/nm/bin/sqlite3 "$SQLITE" "PRAGMA wal_checkpoint(TRUNCATE);" \
  && printf "---- %s WAL CHECKPOINT DONE ----\n" "$(date)" >> "$LOG"

# 2) Copy only the main DB if it changed
$RCLONE --config="$CONF" copy "$SRC/KoboReader.sqlite" "$DEST" \
  --update $RCOPY_FAST_FLAGS >> "$LOG" 2>&1 \
  && printf "---- %s DB COPY (if-changed) DONE ----\n" "$(date)" >> "$LOG"

# 3) Copy only new markup images since last run
NEW_LIST=/mnt/onboard/.adds/nm/new_markups.txt
# Generate list of new SVG/JPGs modified after last log entry
find "$SRC/markups" -type f \( -iname '*.svg' -o -iname '*.jpg' \) \
     -newer "$LOG" > "$NEW_LIST"

if [ -s "$NEW_LIST" ]; then
  COUNT=$(wc -l < "$NEW_LIST")
  $RCLONE --config="$CONF" copy "$SRC" "$DEST" \
    --files-from "$NEW_LIST" $RCOPY_FAST_FLAGS >> "$LOG" 2>&1 \
    && printf "---- %s UPLOADED %d NEW MARKUPS ----
" "$(date)" "$COUNT" >> "$LOG"
else
  printf "---- %s NO NEW MARKUPS TO UPLOAD ----
" "$(date)" >> "$LOG"
fi

# 4) Calculate duration
END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))

# 5) Notify via Telegram (seconds only)
MSG="✅%20Kobo%20Sync%20complete%21%20Duration%3A%20${ELAPSED}s"
nohup "$WGET" -qO- \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage?chat_id=${CHAT_ID}&text=${MSG}" \
  >/dev/null 2>&1 &

printf "---- %s COMPLETE (Duration: %ss) ----\n" "$(date)" "$ELAPSED" >> "$LOG"