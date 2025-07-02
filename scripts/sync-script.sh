#!/bin/sh

# Paths
RCLONE=/mnt/onboard/.adds/nm/bin/rclone
SQLITE=/mnt/onboard/.kobo/KoboReader.sqlite
WGET=/usr/bin/wget

# Load Telegram credentials
TELEGRAM_CONF=/mnt/onboard/.config/telegram/telegram.conf
. "$TELEGRAM_CONF"

# Logging & config
LOG=/mnt/onboard/SyncNotes.log
CONF=/mnt/onboard/.config/rclone/rclone.conf
SRC=/mnt/onboard/.kobo
DEST=b2:KoboSync/kobo

# Performance tuning flags
RCOPY_FAST_FLAGS="--fast-list --transfers 8 --checkers 4"

# 1) Start sync
printf "---- %s START SYNC ----\n" "$(date)" >> "$LOG"
START_TS=$(date +%s)

# 2) Merge WAL into main DB
/mnt/onboard/.adds/nm/bin/sqlite3 "$SQLITE" "PRAGMA wal_checkpoint(TRUNCATE);" \
  && printf "---- %s WAL CHECKPOINT DONE ----\n" "$(date)" >> "$LOG"

# 3) Copy DB if changed
$RCLONE --config="$CONF" copy "$SRC/KoboReader.sqlite" "$DEST" \
  --update $RCOPY_FAST_FLAGS >> "$LOG" 2>&1 \
  && printf "---- %s DB COPY (if-changed) DONE ----\n" "$(date)" >> "$LOG"

# 4) Mirror markups (additions & deletions), skip unchanged
$RCLONE --config="$CONF" sync "$SRC/markups" "$DEST/markups" \
  --ignore-existing $RCOPY_FAST_FLAGS \
  --filter "+ *.svg" \
  --filter "+ *.jpg" \
  --filter "- *" >> "$LOG" 2>&1 \
  && printf "---- %s MARKUPS SYNCED (adds & deletes) ----\n" "$(date)" >> "$LOG"

# 5) Calculate duration
END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))

# 6) Notify via Telegram
MSG="✅ Kobo Sync complete! Duration: ${ELAPSED}s"
ENC=$(echo "$MSG" | sed -e 's/ /%20/g' -e 's/!/%%21/g')
nohup "$WGET" -qO- \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage?chat_id=${CHAT_ID}&text=${ENC}" \
  >> "$LOG" 2>&1 &

# 7) Complete log
printf "---- %s COMPLETE (Duration: %ss) ----\n" "$(date)" "$ELAPSED" >> "$LOG"