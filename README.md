# Pi Photo Slideshow

A fullscreen photo slideshow served by Apache2 on a Raspberry Pi. Photos are displayed with a fade-to-black transition and filename-based captions. New photos added over the network appear automatically within 60 seconds — no restart required.

---

## Quick install

On a fresh Raspberry Pi OS install, clone the repo and run the setup script:

```bash
git clone https://github.com/glenmo/pi-photo-slideshow.git ~/slideshow
cd ~/slideshow
chmod +x setup.sh
./setup.sh
```

The script automatically:
- Installs Apache2, Python3, and Samba
- Creates and enables a virtual host at `http://<hostname>.local/`
- Deploys `index.html` and `scan_photos.py`
- Sets up the cron job to scan for new photos every minute
- Configures a Samba share for drag-and-drop from Mac/PC
- Detects compositor (labwc or LXDE) and sets up Chromium kiosk mode on boot
- Detects `chromium` vs `chromium-browser` binary automatically
- Applies GPU memory tweaks for smooth display (Pi 3)

After the script finishes:

```bash
# Set a Samba password for drag-and-drop access from Mac/PC
sudo smbpasswd -a <your-username>

# Add some photos
scp photo.jpg <user>@<hostname>.local:/var/www/<hostname>.local/photos/

# Reboot into kiosk mode
sudo reboot
```

---

## Tested on

| Hardware | OS | Compositor | Status |
|---|---|---|---|
| Raspberry Pi 5 | Pi OS Bookworm | LXDE | Working |
| Raspberry Pi 3 | Pi OS Bookworm | labwc | Working |

---

## How it works

- `index.html` — fullscreen slideshow page served by Apache2
- `scan_photos.py` — scans the photos folder, fixes file permissions, and writes `photos.json`
- A cron job runs `scan_photos.py` every minute
- The browser fetches `photos.json` every 60 seconds and picks up any new photos automatically

---

## Requirements

- Raspberry Pi 3 or newer
- Raspberry Pi OS (Debian Bookworm or later)
- Desktop environment (for kiosk mode)
- Network connection

All other dependencies (Apache2, Python3, Samba, Chromium) are installed by `setup.sh`.

---

## Manual installation

If you prefer to set things up step by step rather than using the script, replace `<hostname>` with your Pi's hostname and `<user>` with your username throughout.

### 1. Clone the repo

```bash
git clone https://github.com/glenmo/pi-photo-slideshow.git ~/slideshow
```

### 2. Write the config file

```bash
cat > ~/.slideshow_config << EOF
PHOTO_DIR=/var/www/<hostname>.local/photos
OUTPUT=/var/www/<hostname>.local/photos.json
EOF
```

### 3. Set up the Apache2 virtual host

Create the document root and set permissions:

```bash
sudo mkdir -p /var/www/<hostname>.local/photos
sudo chown -R <user>:www-data /var/www/<hostname>.local
sudo chmod -R 775 /var/www/<hostname>.local
```

Create the virtual host config:

```bash
sudo nano /etc/apache2/sites-available/<hostname>.local.conf
```

Paste:

```apache
<VirtualHost *:80>
    ServerName <hostname>.local
    ServerAlias www.<hostname>.local
    DocumentRoot /var/www/<hostname>.local
    <Directory /var/www/<hostname>.local>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog ${APACHE_LOG_DIR}/<hostname>.local-error.log
    CustomLog ${APACHE_LOG_DIR}/<hostname>.local-access.log combined
</VirtualHost>
```

Enable the site and reload Apache:

```bash
sudo a2ensite <hostname>.local.conf
sudo systemctl reload apache2
```

### 4. Deploy the slideshow files

```bash
sudo cp ~/slideshow/index.html /var/www/<hostname>.local/index.html
cp ~/slideshow/scan_photos.py ~/scan_photos.py
```

### 5. Run the scanner once to test

```bash
python3 ~/scan_photos.py
cat /var/www/<hostname>.local/photos.json
```

You should see `[]` if no photos have been added yet — that's fine.

### 6. Set up the cron job

```bash
crontab -e
```

Add this line:

```
* * * * * python3 /home/<user>/scan_photos.py
```

### 7. Set up kiosk mode on boot

First check which compositor your Pi OS uses:

```bash
ls ~/.config/labwc/    # exists on Pi OS Bookworm (Pi 3)
ls ~/.config/lxsession/ # exists on older Pi OS (Pi 5 / LXDE)
```

Also check the Chromium binary name:

```bash
which chromium         # Pi OS Bookworm
which chromium-browser # older Pi OS
```

**For labwc (Pi OS Bookworm — Pi 3):**

```bash
cat >> ~/.config/labwc/autostart << 'EOF'
xset s off &
xset -dpms &
xset s noblank &
sleep 5 && chromium --kiosk --no-first-run --noerrdialogs --disable-infobars --incognito --disable-restore-session-state http://<hostname>.local &
EOF
```

**For LXDE (older Pi OS — Pi 5):**

```bash
nano ~/.config/lxsession/LXDE-pi/autostart
```

Add at the bottom:

```
@xset s off
@xset -dpms
@xset s noblank
@chromium-browser --kiosk --no-first-run --noerrdialogs --disable-infobars --incognito --disable-restore-session-state http://<hostname>.local
```

Reboot to test:

```bash
sudo reboot
```

---

## Adding photos

### From a Mac or Linux machine (command line)

Copy a single photo:

```bash
scp photo.jpg <user>@<hostname>.local:/var/www/<hostname>.local/photos/
```

Copy a folder of photos:

```bash
scp -r ~/Photos/album/* <user>@<hostname>.local:/var/www/<hostname>.local/photos/
```

### Drag and drop via Samba (recommended)

Samba is installed automatically by `setup.sh`. Set a password and connect:

```bash
sudo smbpasswd -a <user>
sudo systemctl restart smbd
```

On your Mac, open Finder and press `Cmd+K`, then connect to:

```
smb://<hostname>.local/photos
```

The photos folder mounts as a network drive — drag and drop photos directly from your Mac.

> **Note for Mac users:** macOS creates hidden `._` metadata files alongside photos when copying over a network share. These are automatically filtered out by `scan_photos.py` and will not appear in the slideshow.

---

## Caption naming convention

Captions are generated automatically from filenames. For best results use underscores or hyphens as word separators — no spaces needed.

| Filename | Caption displayed |
|---|---|
| `pip_and_milo_school_pickup.jpg` | Pip and Milo School Pickup |
| `moora_moora_1.jpg` | Moora Moora 1 |
| `sliding_doors_2.jpg` | Sliding Doors 2 |
| `family-christmas-2024.jpg` | Family Christmas 2024 |

---

## Keyboard controls

When a keyboard is connected to the Pi:

| Key | Action |
|---|---|
| `Space` or `→` | Next photo |
| `←` | Previous photo |
| `Esc` or `q` | Pause / resume |

---

## Slideshow settings

Settings are at the top of `index.html` and can be adjusted:

```javascript
const INTERVAL_MS   = 10000;     // time per photo in milliseconds (10000 = 10s)
const FADE_MS       = 1500;      // fade duration in milliseconds
const CAPTION_DELAY = 400;       // delay before caption appears after image fades in
const ORDER         = 'random';  // 'random' or 'sequential'
const FIT           = 'contain'; // 'contain' (letterbox) or 'cover' (crop to fill)
```

After editing, redeploy:

```bash
sudo cp ~/slideshow/index.html /var/www/<hostname>.local/index.html
```

---

## Updating from GitHub

To pull the latest version of the slideshow onto the Pi:

```bash
cd ~/slideshow
git pull
sudo cp index.html /var/www/<hostname>.local/index.html
cp scan_photos.py ~/scan_photos.py
```

## Pushing changes to GitHub

After editing files:

```bash
cd ~/slideshow
git add -A
git commit -m "describe your change"
git push
```

---

## Troubleshooting

**Black screen / broken image icon**

Check Apache error log:
```bash
sudo tail -20 /var/log/apache2/<hostname>.local-error.log
```

If you see `Permission denied`, fix photo file permissions:
```bash
sudo chmod 644 /var/www/<hostname>.local/photos/*.jpg
```

The cron job handles this automatically for newly added photos going forward.

**Photos not updating**

Check that the cron job is running and `photos.json` is being updated:
```bash
python3 ~/scan_photos.py
cat /var/www/<hostname>.local/photos.json
```

**Site not found at hostname.local**

Check the virtual host is enabled:
```bash
ls /etc/apache2/sites-enabled/
sudo a2ensite <hostname>.local.conf
sudo systemctl reload apache2
```

**Kiosk mode not starting on boot**

Check which compositor is running:
```bash
ls ~/.config/labwc/    # labwc = Pi OS Bookworm
ls ~/.config/lxsession/ # LXDE = older Pi OS
```

Check the correct autostart file has the chromium entry:
```bash
cat ~/.config/labwc/autostart         # for labwc
cat ~/.config/lxsession/LXDE-pi/autostart  # for LXDE
```

Check the correct chromium binary name:
```bash
which chromium
which chromium-browser
```

Test kiosk mode manually without rebooting:
```bash
chromium --kiosk --no-first-run --noerrdialogs --disable-infobars --incognito --disable-restore-session-state http://<hostname>.local
```

**Chromium shows Google login prompt on first launch**

The `--no-first-run` and `--incognito` flags suppress this. Make sure your autostart entry includes both flags as shown above.

**GitHub push failing (SSH timeout)**

If SSH to GitHub hangs, port 22 may be blocked. Force SSH over port 443:

```bash
nano ~/.ssh/config
```

Add:
```
Host github.com
  Hostname ssh.github.com
  Port 443
  User git
```

Test with:
```bash
ssh -T git@github.com
```

**macOS `._` metadata files appearing in photos folder**

Delete them — `scan_photos.py` filters them automatically going forward:
```bash
find /var/www/<hostname>.local/photos/ -name "._*" -delete
```

---

## File structure

```
repo/
├── index.html        # slideshow page — deploy to DocumentRoot
├── scan_photos.py    # photo scanner — run via cron from home directory
├── setup.sh          # automated setup script for fresh Pi OS install
└── README.md

/var/www/<hostname>.local/
├── index.html        # deployed slideshow page
├── photos.json       # auto-generated by scan_photos.py
└── photos/           # put your photos here
    ├── photo_one.jpg
    └── photo_two.jpg

~/.slideshow_config   # paths config written by setup.sh
~/.config/labwc/autostart          # kiosk autostart (Pi OS Bookworm)
~/.config/lxsession/LXDE-pi/autostart  # kiosk autostart (older Pi OS)
```
