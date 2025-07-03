#!/usr/bin/env python3
"""
organise_kobo_markups.py

1) Syncs KoboReader data from B2 via rclone
2) Parses the SQLite database and markup files
3) Generates overlayed PNGs grouped by book title
4) Writes outputs into an Obsidian vault folder

Usage:
    python organise_kobo_markups.py

Dependencies:
    pip install cairosvg pillow
"""
import os
import sys
import sqlite3
import subprocess
from pathlib import Path
from io import BytesIO
from PIL import Image
import cairosvg

# Configuration
RCLONE_REMOTE = 'b2:KoboSync/kobo'
SYNC_DIR = Path.home() / 'KoboNotes'
VAULT_DIR = Path.home() / 'ObsidianVault' / 'KoboMarkups'

# Image size
WIDTH, HEIGHT = 1264, 1680


def sync_data():
    print(f"Syncing from {RCLONE_REMOTE} to {SYNC_DIR}...")
    try:
        subprocess.run([
            'rclone', 'sync', RCLONE_REMOTE, str(SYNC_DIR)
        ], check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error during rclone sync: {e}")
        sys.exit(1)


def find_pairs(markup_root):
    file_map = {}
    for path in markup_root.rglob('*'):
        if path.suffix.lower() in ('.jpg', '.svg'):
            base = path.stem
            file_map.setdefault(base, {})[path.suffix.lower()] = path
    # Only keep those with both jpg and svg
    return [ (base, paths['.jpg'], paths['.svg'])
             for base, paths in file_map.items()
             if '.jpg' in paths and '.svg' in paths ]


def sanitize(name):
    return "".join(c if c.isalnum() or c in (' ', '-', '_') else '_' for c in name).strip()


def parse_location(start_path):
    if not start_path:
        return 'LocX'
    import re
    m = re.search(r"point\(([^)]+)\)", start_path)
    if m:
        return m.group(1).replace(':', '.').replace('/', '.')
    return 'LocX'


def overlay(jpg_path, svg_path, output_path):
    # Load base image
    base = Image.open(jpg_path).convert('RGBA')
    base = base.resize((WIDTH, HEIGHT))
    # Render SVG to PNG in-memory
    svg_bytes = cairosvg.svg2png(url=str(svg_path), output_width=WIDTH, output_height=HEIGHT)
    overlay_img = Image.open(BytesIO(svg_bytes)).convert('RGBA')
    # Composite
    combined = Image.alpha_composite(base, overlay_img)
    # Save
    combined.convert('RGB').save(output_path, 'PNG')


def process():
    sync_data()
    VAULT_DIR.mkdir(parents=True, exist_ok=True)

    sqlite_file = SYNC_DIR / 'KoboReader.sqlite'
    if not sqlite_file.exists():
        print(f"SQLite file not found at {sqlite_file}")
        sys.exit(1)

    markup_folder = SYNC_DIR / 'markups'
    if not markup_folder.exists():
        print(f"Markup folder not found at {markup_folder}")
        sys.exit(1)

    pairs = find_pairs(markup_folder)
    print(f"Found {len(pairs)} markup pairs.")

    conn = sqlite3.connect(sqlite_file)
    cursor = conn.cursor()

    for base, jpg, svg in pairs:
        # Metadata queries
        cursor.execute("SELECT VolumeID FROM Bookmark WHERE BookmarkID = ?", (base,))
        volume = cursor.fetchone()
        volume = volume[0] if volume else None

        cursor.execute(
            "SELECT Title FROM content WHERE ContentID = (SELECT ContentID FROM Bookmark WHERE BookmarkID = ?)", (base,)
        )
        section = cursor.fetchone()
        section = section[0] if section and section[0].strip() else 'UnknownSection'

        cursor.execute(
            "SELECT adobe_location FROM content WHERE ContentID = (SELECT ContentID FROM Bookmark WHERE BookmarkID = ?)", (base,)
        )
        adobe = cursor.fetchone()
        part = Path(adobe[0]).stem if adobe and adobe[0] else 'PartX'

        cursor.execute(
            "SELECT StartContainerPath FROM Bookmark WHERE BookmarkID = ?", (base,)
        )
        start = cursor.fetchone()
        loc = parse_location(start[0] if start else '')

        book = Path(volume).name.replace('.', '_') if volume else 'UnknownBook'
        book = sanitize(book)
        section = sanitize(section)

        short = base[:8]
        outfile = f"markup_{section}_{part}_{loc}_{short}.png"
        book_dir = VAULT_DIR / book
        book_dir.mkdir(parents=True, exist_ok=True)
        outpath = book_dir / outfile

        try:
            print(f"Processing {base} -> {outpath.name}")
            overlay(jpg, svg, outpath)
        except Exception as e:
            print(f"Failed {base}: {e}")

    conn.close()
    print("Done. All markups are in your Obsidian vault.")


if __name__ == '__main__':
    process()