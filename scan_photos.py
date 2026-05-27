#!/usr/bin/env python3
"""
Scan the source photo folder, pre-scale new/changed images to the display
resolution, and write photos.json for the slideshow to consume.

The browser only ever loads the pre-scaled copies (in CACHE_DIR), which keeps
memory stable over long uptimes. Originals live in PHOTO_DIR (the Samba drop
folder) and are never served directly.

Run periodically by cron — see setup.sh.
"""
import os, json, time
from urllib.parse import quote

try:
    from PIL import Image, ImageOps
except ImportError:
    raise SystemExit(
        "Pillow is required. Install with: sudo apt-get install -y python3-pil"
    )

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

config     = load_config()
PHOTO_DIR  = config.get("PHOTO_DIR",  "/home/glen/photos")
CACHE_DIR  = config.get("CACHE_DIR",  "/var/www/rubberduck.local/photos")
OUTPUT     = config.get("OUTPUT",     "/var/www/rubberduck.local/photos.json")
MAX_W      = int(config.get("DISPLAY_WIDTH",  "3840"))
MAX_H      = int(config.get("DISPLAY_HEIGHT", "2160"))

EXTS           = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
STABILITY_WAIT = 2  # seconds a file's size must stay unchanged before we load it

# Map source extension -> Pillow save format, preserving format so the cached
# filename (and therefore the caption) is identical to the original.
SAVE_FORMAT = {
    ".jpg": "JPEG", ".jpeg": "JPEG",
    ".png": "PNG", ".webp": "WEBP", ".gif": "GIF",
}


def is_photo(name):
    """A real image file, not a hidden/metadata file (.DS_Store, ._*, dotfiles)."""
    if name.startswith("."):
        return False
    return os.path.splitext(name)[1].lower() in EXTS


def needs_rescale(src, dst):
    """True if the cached copy is missing or older than the original."""
    if not os.path.exists(dst):
        return True
    try:
        return os.path.getmtime(src) > os.path.getmtime(dst)
    except OSError:
        return True


def scale_image(src, dst, fmt):
    """Downscale src to fit MAX_W x MAX_H (never upscale) and write to dst."""
    with Image.open(src) as img:
        img = ImageOps.exif_transpose(img)  # honour camera rotation
        img.thumbnail((MAX_W, MAX_H), Image.LANCZOS)  # shrinks only, keeps aspect

        tmp = dst + ".tmp"
        if fmt == "JPEG":
            if img.mode not in ("RGB", "L"):
                img = img.convert("RGB")  # JPEG has no alpha
            img.save(tmp, "JPEG", quality=85, optimize=True, progressive=True)
        elif fmt == "WEBP":
            img.save(tmp, "WEBP", quality=85, method=6)
        elif fmt == "PNG":
            img.save(tmp, "PNG", optimize=True)
        else:  # GIF (first frame)
            img.save(tmp, "GIF")

    os.chmod(tmp, 0o644)  # Apache (www-data) must be able to read it
    os.replace(tmp, dst)  # atomic — slideshow never sees a half-written file


os.makedirs(CACHE_DIR, exist_ok=True)

originals = sorted(f for f in os.listdir(PHOTO_DIR) if is_photo(f))

# Work out which files need (re)scaling, then confirm their size is stable so a
# photo still copying over Samba is deferred to the next scan instead of erroring.
pending = [f for f in originals if needs_rescale(
    os.path.join(PHOTO_DIR, f), os.path.join(CACHE_DIR, f))]

stable = []
if pending:
    sizes_before = {}
    for f in pending:
        try:
            sizes_before[f] = os.path.getsize(os.path.join(PHOTO_DIR, f))
        except OSError:
            pass
    time.sleep(STABILITY_WAIT)
    for f, size in sizes_before.items():
        try:
            if os.path.getsize(os.path.join(PHOTO_DIR, f)) == size:
                stable.append(f)
            else:
                print(f"Skipping (still copying): {f}")
        except OSError:
            pass

for f in stable:
    try:
        fmt = SAVE_FORMAT[os.path.splitext(f)[1].lower()]
        scale_image(os.path.join(PHOTO_DIR, f), os.path.join(CACHE_DIR, f), fmt)
    except Exception as e:
        print(f"Failed to scale {f}: {e}")

# Remove cached copies whose original has been deleted.
for f in os.listdir(CACHE_DIR):
    if f.endswith(".tmp") or f not in originals:
        try:
            os.remove(os.path.join(CACHE_DIR, f))
        except OSError:
            pass

# The slideshow list is every original that currently has a ready cached copy.
ready = sorted(f for f in originals
               if os.path.exists(os.path.join(CACHE_DIR, f)))
files = [f"/photos/{quote(f)}" for f in ready]

tmp_json = OUTPUT + ".tmp"
with open(tmp_json, "w") as out:
    json.dump(files, out)
os.replace(tmp_json, OUTPUT)  # atomic write

print(f"{len(files)} photos ready, {len(stable)} (re)scaled this run.")
