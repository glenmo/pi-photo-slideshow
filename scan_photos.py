import os, json, subprocess
from urllib.parse import quote

PHOTO_DIR = "/var/www/rubberduck.local/photos"
OUTPUT    = "/var/www/rubberduck.local/photos.json"
EXTS      = {".jpg", ".jpeg", ".png", ".webp", ".gif"}

files = sorted([
    f"/photos/{quote(f)}" for f in os.listdir(PHOTO_DIR)
    if os.path.splitext(f)[1].lower() in EXTS
])

# Fix permissions on any newly added photos
for f in os.listdir(PHOTO_DIR):
    if os.path.splitext(f)[1].lower() in EXTS:
        path = os.path.join(PHOTO_DIR, f)
        os.chmod(path, 0o644)

with open(OUTPUT, "w") as out:
    json.dump(files, out)

print(f"Found {len(files)} photos.")
