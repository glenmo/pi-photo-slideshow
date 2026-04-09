#!/usr/bin/env python3
import os, json
from urllib.parse import quote

# Path is written by setup.sh into ~/.slideshow_config
CONFIG_FILE = os.path.expanduser("~/.slideshow_config")

def load_config():
    config = {}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    config[k.strip()] = v.strip()
    return config

config    = load_config()
PHOTO_DIR = config.get("PHOTO_DIR", "/var/www/rubberduck.local/photos")
OUTPUT    = config.get("OUTPUT",    "/var/www/rubberduck.local/photos.json")
EXTS      = {".jpg", ".jpeg", ".png", ".webp", ".gif"}

# Build sorted list of photo URLs
files = sorted([
    f"/photos/{quote(f)}" for f in os.listdir(PHOTO_DIR)
if os.path.splitext(f)[1].lower() in EXTS and not f.startswith("._")
])

# Fix permissions on any newly added photos
for f in os.listdir(PHOTO_DIR):
    if os.path.splitext(f)[1].lower() in EXTS:
        path = os.path.join(PHOTO_DIR, f)
        try:
            os.chmod(path, 0o644)
        except PermissionError:
            pass

with open(OUTPUT, "w") as out:
    json.dump(files, out)

print(f"Found {len(files)} photos.")
