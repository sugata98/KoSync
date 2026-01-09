#!/bin/sh

# --- CONFIGURATION ---
# Load API key from config file (same pattern as sync_notes.sh)
AI_CONF=/mnt/onboard/.config/kobo-ai/kobo-ai.conf
. "$AI_CONF"

# API_URL and API_KEY are now loaded from config
# Defaults (override in config if needed)
API_URL="${API_URL:-https://api.readr.space/kobo-ask}"
DB_PATH="/mnt/onboard/.kobo/KoboReader.sqlite"
SQLITE_BIN="/mnt/onboard/.adds/nm/bin/sqlite3"

# Debug log file
LOG_FILE="/mnt/onboard/kobo-ask-debug.log"

# Start logging
echo "========================================" >> "$LOG_FILE"
echo "Script started at: $(date)" >> "$LOG_FILE"

# Use static curl from scripts directory
# $0 is the script path, we use dirname to find curl in the same folder
SCRIPT_DIR=$(dirname "$0")
CURL_BIN="$SCRIPT_DIR/curl"

echo "Script directory: $SCRIPT_DIR" >> "$LOG_FILE"
echo "Looking for curl at: $CURL_BIN" >> "$LOG_FILE"

# Give execute permissions just in case
chmod +x "$CURL_BIN" 2>> "$LOG_FILE"

# Verify curl exists
if [ ! -x "$CURL_BIN" ]; then
    echo "ERROR: Static curl not found at $CURL_BIN" >> "$LOG_FILE"
    qndb -m mng -t 3000 -c "Error" -n "curl binary not found in scripts folder"
    exit 1
fi

echo "Using static curl: $CURL_BIN" >> "$LOG_FILE"

# --- 1. HELPER FUNCTIONS ---

# Function to decode URL-encoded text (Pure Shell, no Python needed)
# NickelMenu usually passes sanitized text, but this is a safety net.
urldecode() { : "${*//+/ }"; echo -e "${_//%/\\x}"; }

# --- 2. INPUT HANDLING ---

# Get raw input from NickelMenu
# {1|aS|"$"} passes text with stripped newlines and escaped quotes.
RAW_TEXT="$1"

echo "Raw input received: '$RAW_TEXT'" >> "$LOG_FILE"

# If simple text is passed, just use it. 
# If you ever switch to URL-encoded mode in NickelMenu, uncomment the next line:
# TEXT=$(urldecode "$RAW_TEXT")
TEXT="$RAW_TEXT"

if [ -z "$TEXT" ]; then
    # Show error toast if selection failed
    echo "ERROR: No text selected" >> "$LOG_FILE"
    qndb -m mng -t 2000 -c "Error" -n "No text selected."
    exit 1
fi

echo "Text to process: '${TEXT:0:100}...'" >> "$LOG_FILE"

# --- 3. CONTEXT RETRIEVAL (Simplified single-line query for BusyBox compatibility) ---

# Debug: Check if database exists and is accessible
if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Database not found at $DB_PATH" >> "$LOG_FILE"
else
    echo "Database exists at $DB_PATH" >> "$LOG_FILE"
fi

# Simplified single-line query using full path to sqlite3
# Try Query 1: Most recently read book
META_RAW=$("$SQLITE_BIN" -separator "|" "$DB_PATH" "SELECT Title, Attribution, ContentID FROM content WHERE ContentType = '6' AND (BookID IS NULL OR BookID = '') AND Title IS NOT NULL AND ContentID NOT LIKE '%.png' AND ContentID NOT LIKE '%.jpg' AND ContentID NOT LIKE 'file:///mnt/onboard/kfmon%' ORDER BY DateLastRead DESC LIMIT 1;" 2>&1)
SQL_EXIT=$?
echo "Query 1 exit code: $SQL_EXIT" >> "$LOG_FILE"
echo "Query 1 result: '$META_RAW'" >> "$LOG_FILE"

# If Query 1 fails or returns empty, try simpler fallback
if [ -z "$META_RAW" ] || [ $SQL_EXIT -ne 0 ]; then
    echo "Query 1 failed, trying fallback..." >> "$LOG_FILE"
    META_RAW=$("$SQLITE_BIN" -separator "|" "$DB_PATH" "SELECT Title, Attribution, ContentID FROM content WHERE ContentType = '6' AND Title IS NOT NULL ORDER BY DateLastRead DESC LIMIT 1;" 2>&1)
    echo "Query 2 (fallback) result: '$META_RAW'" >> "$LOG_FILE"
fi

# Parse Results
BOOK_TITLE=$(echo "$META_RAW" | cut -d'|' -f1)
AUTHOR=$(echo "$META_RAW" | cut -d'|' -f2)
BOOK_CONTENT_ID=$(echo "$META_RAW" | cut -d'|' -f3)

echo "Parsed - Title: '$BOOK_TITLE', Author: '$AUTHOR', ContentID: '$BOOK_CONTENT_ID'" >> "$LOG_FILE"

# Try to get chapter info (ContentType='899' are TOC entries)
# THREE-STEP PROCESS to detect CURRENT chapter (not just first chapter):
if [ -n "$BOOK_CONTENT_ID" ]; then
    # Step 1: Get current reading position from Bookmark table
    CURRENT_CONTENT_ID=$("$SQLITE_BIN" "$DB_PATH" "SELECT ContentID FROM Bookmark WHERE VolumeID = '$BOOK_CONTENT_ID' ORDER BY DateCreated DESC LIMIT 1;" 2>/dev/null)
    echo "Current reading ContentID: '$CURRENT_CONTENT_ID'" >> "$LOG_FILE"
    
    # Step 2: Extract part number from ContentID (e.g., "part0025" from "part0025_split_002.html")
    if [ -n "$CURRENT_CONTENT_ID" ]; then
        PART_NUM=$(echo "$CURRENT_CONTENT_ID" | grep -o 'part[0-9]\+' | head -1)
        echo "Extracted part number: '$PART_NUM'" >> "$LOG_FILE"
        
        # Step 3: Find TOC entry matching this part number
        if [ -n "$PART_NUM" ]; then
            CHAPTER=$("$SQLITE_BIN" "$DB_PATH" "SELECT Title FROM content WHERE ContentType = '899' AND BookID = '$BOOK_CONTENT_ID' AND ContentID LIKE '%$PART_NUM%' ORDER BY Depth ASC, VolumeIndex ASC LIMIT 1;" 2>/dev/null)
            echo "Chapter from part match: '$CHAPTER'" >> "$LOG_FILE"
        fi
    fi
    
    # FALLBACK 1: If no match, try to get chapter with "CHAPTER" in title (first one)
    if [ -z "$CHAPTER" ]; then
        echo "No chapter from bookmark, trying CHAPTER keyword..." >> "$LOG_FILE"
        CHAPTER=$("$SQLITE_BIN" "$DB_PATH" "SELECT Title FROM content WHERE ContentType = '899' AND Depth = 1 AND BookID = '$BOOK_CONTENT_ID' AND VolumeIndex > 1 AND (Title LIKE 'CHAPTER%' OR Title LIKE 'Chapter%') ORDER BY VolumeIndex LIMIT 1;" 2>/dev/null)
    fi
    
    # FALLBACK 2: If still no chapter, get any TOC entry after index 1
    if [ -z "$CHAPTER" ]; then
        echo "No CHAPTER keyword, trying any TOC entry..." >> "$LOG_FILE"
        CHAPTER=$("$SQLITE_BIN" "$DB_PATH" "SELECT Title FROM content WHERE ContentType = '899' AND Depth = 1 AND BookID = '$BOOK_CONTENT_ID' AND VolumeIndex > 1 ORDER BY VolumeIndex LIMIT 1;" 2>/dev/null)
    fi
    
    echo "Final chapter result: '$CHAPTER'" >> "$LOG_FILE"
fi

# Final Fallbacks
if [ -z "$BOOK_TITLE" ]; then BOOK_TITLE="Current Reading"; fi
if [ -z "$AUTHOR" ]; then AUTHOR="Author Unknown"; fi
if [ -z "$CHAPTER" ]; then CHAPTER="Current Location"; fi

echo "Final Context - Book: '$BOOK_TITLE', Author: '$AUTHOR', Chapter: '$CHAPTER'" >> "$LOG_FILE"

# --- 4. JSON CONSTRUCTION ---

# Sanitize inputs for JSON (Escape double quotes and backslashes)
# Critical: Malformed JSON will cause the API call to fail silently.
SAFE_TEXT=$(echo "$TEXT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
SAFE_TITLE=$(echo "$BOOK_TITLE" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
SAFE_AUTHOR=$(echo "$AUTHOR" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
SAFE_CHAPTER=$(echo "$CHAPTER" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

# Build the JSON string safely
JSON_DATA=$(cat <<EOF
{
  "mode": "explain",
  "text": "$SAFE_TEXT",
  "context": {
    "book": "$SAFE_TITLE",
    "author": "$SAFE_AUTHOR",
    "chapter": "$SAFE_CHAPTER",
    "device_id": "kobo-sarthak"
  }
}
EOF
)

echo "JSON payload constructed (first 200 chars): ${JSON_DATA:0:200}..." >> "$LOG_FILE"

# --- 5. EXECUTION ---

# Ensure Network is up (Non-blocking attempt)
echo "Attempting to wake WiFi..." >> "$LOG_FILE"
qndb -m pwc --timeout 5

# Send Request using static curl
# -k: Allow insecure SSL (fixes old Kobo certs)
# -s: Silent mode
# -f: Fail silently on server error
# -m 20: Max time 20 seconds (AI takes time to think!)
echo "Sending request to: $API_URL" >> "$LOG_FILE"
echo "Request timestamp: $(date +%s)" >> "$LOG_FILE"
echo "JSON payload (first 200 chars): ${JSON_DATA:0:200}..." >> "$LOG_FILE"

RESPONSE=$("$CURL_BIN" -k -s -f -m 20 -X POST "$API_URL" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$JSON_DATA")

CURL_EXIT=$?

echo "curl exit code: $CURL_EXIT" >> "$LOG_FILE"
echo "Response timestamp: $(date +%s)" >> "$LOG_FILE"

# --- 6. USER FEEDBACK (The Native Dialog) ---

if [ $CURL_EXIT -eq 0 ] && [ -n "$RESPONSE" ]; then
    # Success: Output to stdout (NickelMenu's cmd_output will display this)
    # Backend returns a SHORT summary (1-2 sentences, max 200 chars)
    # Full analysis is sent to Telegram automatically
    echo "SUCCESS: Response received (${#RESPONSE} chars)" >> "$LOG_FILE"
    echo "Response: '$RESPONSE'" >> "$LOG_FILE"
    
    # Output to stdout - NickelMenu will show this in a dialog
    echo "✨ AI Explanation"
    echo ""
    echo "$RESPONSE"
    echo ""
    echo "📱 Full analysis sent to Telegram"
    
    echo "Dialog output sent to stdout" >> "$LOG_FILE"
else
    # Error: Output error to stdout
    echo "ERROR: curl failed with exit code $CURL_EXIT or empty response" >> "$LOG_FILE"
    echo "Response (if any): $RESPONSE" >> "$LOG_FILE"
    
    # Output to stdout
    echo "❌ Connection Error"
    echo ""
    echo "Could not reach AI service."
    echo "Please check WiFi connection."
    echo ""
    echo "Error code: $CURL_EXIT"
fi

echo "Script finished at: $(date)" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
