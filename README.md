# Kobo Sync Scripts

Bunch of scripts to keep the notes, annotations, and markups for Kobo Libra Color backed up on the cloud.

---

## What does `90_sync_notes.sh` do?

- Merges the SQLite WAL into the main database for consistency
- Uploads the main `KoboReader.sqlite` database to the cloud (B2) if changed
- Mirrors markups (SVG/JPG) to the cloud—adding new and deleting removed files
- Logs all actions to `/mnt/onboard/SyncNotes.log` on the device
- Sends a Telegram notification when sync completes, including duration

---

## Binaries

The repository includes pre-built ARMv7 binaries for immediate use:

- `bin/sqlite3` (ELF 32-bit ARM, static build)
- `bin/rclone` (ELF 32-bit ARM)

Copy these into NickelMenu’s bin folder on your Kobo:

```sh
cp bin/sqlite3 /mnt/onboard/.adds/nm/bin/sqlite3
cp bin/rclone   /mnt/onboard/.adds/nm/bin/rclone
chmod +x /mnt/onboard/.adds/nm/bin/{sqlite3,rclone}
```

---

## Installation & NickelMenu Integration

### Rclone Configuration

Create your Rclone config at `/mnt/onboard/.config/rclone/rclone.conf`:

```sh
[b2]
type    = b2
account = <your-account-id>
key     = <your-app-key>
```

Secure it:

```sh
chmod 600 /mnt/onboard/.config/rclone/rclone.conf
```

### Telegram Credentials

Create `/mnt/onboard/.config/telegram/telegram.conf`:

```sh
BOT_TOKEN=<your-bot-token>
CHAT_ID=<your-chat-id>
```

Secure it:

```sh
chmod 600 /mnt/onboard/.config/telegram/telegram.conf
```

### Copy Binaries

```sh
cp bin/sqlite3 /mnt/onboard/.adds/nm/bin/sqlite3
cp bin/rclone   /mnt/onboard/.adds/nm/bin/rclone
chmod +x /mnt/onboard/.adds/nm/bin/{sqlite3,rclone}
```

### Install the Sync Script

```sh
mkdir -p /mnt/onboard/.adds/nm/scripts
cp 90_sync_notes.sh /mnt/onboard/.adds/nm/scripts/90_sync_notes.sh
chmod +x /mnt/onboard/.adds/nm/scripts/90_sync_notes.sh
```

### Enable in NickelMenu

To have NickelMenu run the sync on demand, add the script and a menu entry:

1. Ensure the script is present and executable:

```sh
cp 90_sync_notes.sh /mnt/onboard/.adds/nm/scripts/90_sync_notes.sh
chmod +x /mnt/onboard/.adds/nm/scripts/90_sync_notes.sh
```

2. Add the following to your NickelMenu config (`/mnt/onboard/.adds/nm/config`):

```sh
menu_item :main :SyncNotes :cmd_spawn :quiet:exec /mnt/onboard/.adds/nm/scripts/90_sync_notes.sh
```

Now you can select **SyncNotes** from the main menu, and the script will also auto-run on sleep/reboot.

---

## Manual Run & Logs

- In NickelMenu: Scripts → Run script → 90_sync_notes.sh
- Or over SSH:

```sh
sh /mnt/onboard/.adds/nm/scripts/90_sync_notes.sh
tail -f /mnt/onboard/SyncNotes.log
```

---

## Telegram Bot Setup

1. Use BotFather to create a bot and copy its token into `telegram.conf`
2. Send a message to your bot, then run:

```sh
curl "https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates"
```

Note the `chat_id` from the response and set `CHAT_ID` in `telegram.conf`.

---

## Usage on Your Desktop

    # Download latest backup
    rclone copy b2:KoboSync/kobo ~/KoboNotes

    # View annotation count
    sqlite3 ~/KoboNotes/KoboReader.sqlite "SELECT count(*) FROM bookmarks;"

---

## To-Do

- [ ] Add script for organizing markups under Book-name folders
- [ ] Create a UI for showing all annotations, notes, and markups under each book
- [ ] Add additional backup targets (e.g., Google Drive)
- [ ] Add restore functionality to deploy DB and markups back to device
- [ ] Improve error handling and logging verbosity
- [ ] Add configurable scheduling via cron or udev hooks

---

## Done

- [x] Initial sync script for Kobo Libra Color
- [x] Cloud backup to B2 using rclone
- [x] Telegram notification on sync completion
- [x] Markups sync (add & delete)
- [x] WAL checkpoint for SQLite DB

---

## Credits & Licenses

- **SQLite** (public domain)  
  Binaries built from the official SQLite amalgamation (https://sqlite.org). Public-domain software—no attribution required, but appreciated.

- **rclone** (MIT/Apache-2.0)  
  Binaries built from rclone v1.x.y (https://github.com/rclone/rclone). Licensed under MIT and/or Apache-2.0; see [rclone’s license file](https://github.com/rclone/rclone/blob/master/LICENSE.md) for details.
