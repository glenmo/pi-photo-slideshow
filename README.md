# Pi Photo Slideshow

A fullscreen photo slideshow served by Apache2 on a Raspberry Pi. Photos are displayed with a crossfade transition and filename-based captions. New photos added over the network appear automatically within ~30 seconds — no restart required.

Photos dropped into the source folder are **pre-scaled to the display resolution** before being shown, which keeps browser memory stable over long uptimes (no more freezing on large images). Files still copying in over the network are detected and held back until fully written.

---

## Quick install

On a fresh Raspberry Pi OS install, clone the repo and run the setup script:

```bash
git clone git@github.com:glenmo/pi-photo-slideshow.git ~/slideshow
cd ~/slideshow
chmod +x setup.sh
./setup.sh
```

The script automatically:
- Installs Apache2, Python3, Pillow, and Samba
- Creates and enables a virtual host at `http://<hostname>.local/`
- Creates the source photos folder at `~/photos` and a served cache under the web root
- Deploys `index.html` and `scan_photos.py`
- Sets up cron jobs to scan for new photos and pre-scale them every ~30 seconds
- Configures a Samba share on `~/photos` for drag-and-drop from Mac/PC
- Detects compositor (labwc or LXDE) and sets up Chromium kiosk mode on boot
- Detects `chromium` vs `chromium-browser` binary automatically
- Applies GPU memory tweaks for smooth display (Pi 3)

After the script finishes:

```bash
# Set a Samba password for drag-and-drop access from Mac/PC
sudo smbpasswd -a <your-username>

# Add some photos
scp photo.jpg <user>@<hostname>.local:/home/<user>/photos/

# Reboot into kiosk mode
sudo reboot
```

---

## First time GitHub SSH setup

Each Pi needs its own SSH key registered with GitHub before it can clone the repo. Do this once per Pi before running the quick install above.

### 1. Generate an SSH key on the Pi

```bash
ssh-keygen -t ed25519 -C "<hostname>-pi"
```

Press Enter three times to accept the defaults (no passphrase needed).

### 2. Display the public key

```bash
cat ~/.ssh/id_ed25519.pub
```

Copy the entire output line — it starts with `ssh-ed25519`.

### 3. Add the key to GitHub

Go to https://github.com/settings/ssh/new

- **Title**: something descriptive like `rubberduck pi` or `pixel-pi`
- **Key**: paste the output from step 2
- Click **Add SSH key**

### 4. Configure SSH to use port 443

Port 22 (standard SSH) is sometimes blocked on home networks. Force SSH over port 443 which is always open:

```bash
mkdir -p ~/.ssh
cat >> ~/.ssh/config << 'EOF'
Host github.com
  Hostname ssh.github.com
  Port 443
  User git
EOF
```

### 5. Test the connection

```bash
ssh -T git@github.com
```

You should see:

```
Hi glenmo! You've successfully authenticated, but GitHub does not provide shell access.
```

### 6. Set default branch name to main

```bash
git config --global init.defaultBranch main
```

Now proceed with the quick install above.

---

## Tested on

| Hardware | OS | Compositor | Status |
|---|---|---|---|
| Raspberry Pi 5 | Pi OS Bookworm | LXDE | Working |
| Raspberry Pi 3 | Pi OS Bookworm | labwc | Working |

---

## How it works

There are two photo folders:

- **`~/photos`** — the *source* folder where you drop originals (this is the Samba share). The browser never reads from here.
- **`/var/www/<hostname>.local/photos`** — a *cache* of pre-scaled copies that Apache actually serves.

The flow:

- `index.html` — fullscreen slideshow page served by Apache2, crossfading between photos
- `scan_photos.py` — for each original it:
  - skips macOS metadata files (`.DS_Store`, `._*`) and other dotfiles
  - waits until a file's size has been stable for ~2 seconds, so a photo still copying over Samba isn't loaded half-written
  - pre-scales it to the display resolution (downscale only, never enlarged), honouring EXIF rotation, and writes the copy to the served cache
  - deletes cache copies whose original has been removed
  - writes `photos.json` atomically
- Two cron jobs run `scan_photos.py` every ~30 seconds (cron's minimum is 1 minute, so it runs on the minute and again 30s later, guarded by `flock`)
- The browser re-fetches `photos.json` every 30 seconds and picks up any new photos automatically

The pre-scale target resolution is set in `~/.slideshow_config` (`DISPLAY_WIDTH` / `DISPLAY_HEIGHT`).

---

## Requirements

- Raspberry Pi 3 or newer
- Raspberry Pi OS (Debian Bookworm or later)
- Desktop environment (for kiosk mode)
- Network connection

All other dependencies (Apache2, Python3, Pillow, Samba, Chromium) are installed by `setup.sh`.

---

## Manual installation

If you prefer to set things up step by step rather than using the script, replace `<hostname>` with your Pi's hostname and `<user>` with your username throughout.

### 1. Clone the repo

```bash
git clone git@github.com:glenmo/pi-photo-slideshow.git ~/slideshow
```

### 2. Write the config file

```bash
cat > ~/.slideshow_config << EOF
PHOTO_DIR=/home/<user>/photos
CACHE_DIR=/var/www/<hostname>.local/photos
OUTPUT=/var/www/<hostname>.local/photos.json
DISPLAY_WIDTH=3840
DISPLAY_HEIGHT=2160
EOF
```

`PHOTO_DIR` is where you drop originals; `CACHE_DIR` holds the pre-scaled copies Apache serves. Adjust `DISPLAY_WIDTH`/`DISPLAY_HEIGHT` to your screen.

### 3. Set up the Apache2 virtual host

Create the served cache directory, the source photos folder, and set permissions:

```bash
sudo mkdir -p /var/www/<hostname>.local/photos
sudo chown -R <user>:www-data /var/www/<hostname>.local
sudo chmod -R 775 /var/www/<hostname>.local
mkdir -p /home/<user>/photos
```

Also install Pillow, which the scanner uses to pre-scale images:

```bash
sudo apt-get install -y python3-pil
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

Add these two lines (cron's minimum granularity is one minute, so we run twice a minute for ~30s scanning; `flock` stops a slow scan overlapping the next):

```
* * * * * flock -n /tmp/slideshow_scan.lock python3 /home/<user>/scan_photos.py
* * * * * sleep 30 && flock -n /tmp/slideshow_scan.lock python3 /home/<user>/scan_photos.py
```

### 7. Set up kiosk mode on boot

First check which compositor your Pi OS uses:

```bash
ls ~/.config/labwc/     # exists on Pi OS Bookworm (Pi 3)
ls ~/.config/lxsession/ # exists on older Pi OS (Pi 5 / LXDE)
```

Also check the Chromium binary name:

```bash
which chromium          # Pi OS Bookworm
which chromium-browser  # older Pi OS
```

**For labwc (Pi OS Bookworm — Pi 3):**

```bash
cat >> ~/.config/labwc/autostart << 'EOF'
xset s off &
xset -dpms &
xset s noblank &
sleep 5 && chromium --kiosk --no-first-run --noerrdialogs --disable-infobars --password-store=basic --incognito --disable-restore-session-state http://<hostname>.local &
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
@chromium-browser --kiosk --no-first-run --noerrdialogs --disable-infobars --password-store=basic --incognito --disable-restore-session-state http://<hostname>.local
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
scp photo.jpg <user>@<hostname>.local:/home/<user>/photos/
```

Copy a folder of photos:

```bash
scp -r ~/Photos/album/* <user>@<hostname>.local:/home/<user>/photos/
```

### Drag and drop via Samba — Mac

Samba is installed automatically by `setup.sh`. Set a password on the Pi first:

```bash
sudo smbpasswd -a <user>
sudo systemctl restart smbd
```

Open Finder, press `Cmd+K`, and connect to:

```
smb://<hostname>.local/photos
```

Click **Remember this password** so Finder reconnects automatically next time. The photos folder will appear in the Finder sidebar under Locations.

> **Note:** macOS creates hidden `._` and `.DS_Store` metadata files alongside photos when copying over a network share. These (and any other dotfiles) are automatically filtered out by `scan_photos.py` and will not appear in the slideshow.

---

### Drag and drop via Samba — Windows

#### Map as a permanent network drive (recommended)

Mapping the photos folder as a drive letter means it always appears in File Explorer — just open it and drag photos in.

1. Open **File Explorer** (`Windows key + E`)
2. Right-click **This PC** in the left panel → **Map network drive...**
3. Choose a drive letter (e.g. `P:` for Photos)
4. In the **Folder** field enter:
   ```
   \<hostname>.local\photos
   ```
5. Tick **Reconnect at sign-in** and **Connect using different credentials**, then click **Finish**
6. Enter the Pi username and password when prompted, then click **OK**
7. The photos folder opens in File Explorer — drag your photos straight in

Next time, the drive appears under **This PC** automatically.

#### Quick access without mapping a drive

Open File Explorer, click in the address bar, type the path below and press Enter:

```
\<hostname>.local\photos
```

Enter the Pi username and password if prompted. You can drag photos in without any setup, but you will need to type the address each time.

#### Copy via WinSCP (alternative to Samba)

[WinSCP](https://winscp.net) is a free Windows app that connects to the Pi over SSH — no Samba password needed.

1. Download and install WinSCP from https://winscp.net
2. Open WinSCP and create a new session:
   - **File protocol**: SFTP
   - **Host name**: `<hostname>.local`
   - **Username**: your Pi username
   - **Password**: your Pi password
3. Click **Login**
4. Navigate to `/home/<user>/photos/` in the right panel
5. Drag photos from your Windows desktop or folders into the right panel

WinSCP can save the session so you connect with one click next time.

#### Troubleshooting Windows network access

**Can't find the Pi by name** (`<hostname>.local` doesn't resolve)

Windows sometimes struggles with `.local` mDNS names. Try using the Pi's IP address instead:

```
\<ip-address>\photos
```

Ask your system administrator for the Pi's IP address, or find it on the Pi with:
```bash
hostname -I
```

**Access denied / wrong password**

Make sure you have set a Samba password on the Pi:
```bash
sudo smbpasswd -a <user>
```

**Drive doesn't reconnect after restart**

If the mapped drive shows as disconnected after a Windows restart, right-click it in File Explorer and choose **Disconnect**, then remap it following the steps above. This usually happens if Windows tries to connect before the Pi has finished booting.

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
const FADE_MS       = 1500;      // crossfade duration in milliseconds
const CAPTION_DELAY = 400;       // delay before caption appears after image fades in
const ORDER         = 'random';  // 'random' or 'sequential'
const FIT           = 'contain'; // 'contain' (letterbox) or 'cover' (crop to fill)
const REFRESH_MS    = 30000;     // how often to re-check photos.json for new photos
```

After editing, redeploy:

```bash
sudo cp ~/slideshow/index.html /var/www/<hostname>.local/index.html
```

The **pre-scale resolution** is configured separately, in `~/.slideshow_config`:

```
DISPLAY_WIDTH=3840
DISPLAY_HEIGHT=2160
```

After changing these, delete the cached copies so they regenerate at the new size:

```bash
rm -f /var/www/<hostname>.local/photos/*
python3 ~/scan_photos.py
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
crontab -l
python3 ~/scan_photos.py
cat /var/www/<hostname>.local/photos.json
```

If the cron jobs are missing, add them:
```bash
(crontab -l 2>/dev/null
 echo "* * * * * flock -n /tmp/slideshow_scan.lock python3 /home/$(whoami)/scan_photos.py"
 echo "* * * * * sleep 30 && flock -n /tmp/slideshow_scan.lock python3 /home/$(whoami)/scan_photos.py") | crontab -
```

**Slideshow freezes on one image**

Images are pre-scaled to the display resolution before being shown, which keeps memory stable and is the main defence against this. If it still happens, your originals may be scaling to copies that are larger than the screen — lower `DISPLAY_WIDTH`/`DISPLAY_HEIGHT` in `~/.slideshow_config`, clear the cache (`rm -f /var/www/<hostname>.local/photos/*`), and rescan. To recover immediately, restart Chromium:
```bash
sudo systemctl restart lightdm
```

Or press `Ctrl+Shift+R` on a connected keyboard to hard refresh the page.

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
ls ~/.config/labwc/     # labwc = Pi OS Bookworm
ls ~/.config/lxsession/ # LXDE = older Pi OS
```

Check the correct autostart file has the chromium entry:
```bash
cat ~/.config/labwc/autostart              # for labwc
cat ~/.config/lxsession/LXDE-pi/autostart # for LXDE
```

Test kiosk mode manually without rebooting:
```bash
chromium --kiosk --no-first-run --noerrdialogs --disable-infobars --password-store=basic --incognito --disable-restore-session-state http://<hostname>.local
```

**Chromium shows Google login or keyring prompt on first launch**

Make sure your autostart entry includes `--no-first-run`, `--incognito`, and `--password-store=basic` as shown above.

**GitHub SSH permission denied**

The Pi's SSH key hasn't been added to GitHub. Follow the **First time GitHub SSH setup** section above.

**GitHub push failing (SSH timeout)**

Port 22 may be blocked. Force SSH over port 443:

```bash
cat >> ~/.ssh/config << 'EOF'
Host github.com
  Hostname ssh.github.com
  Port 443
  User git
EOF
```

Test with:
```bash
ssh -T git@github.com
```

**macOS `._` metadata files appearing in photos folder**

`scan_photos.py` filters them automatically, so they never reach the slideshow. To tidy the source folder anyway:
```bash
find /home/<user>/photos/ -name "._*" -delete
find /home/<user>/photos/ -name ".DS_Store" -delete
```

---

## File structure

```
repo/
├── index.html        # slideshow page — deploy to DocumentRoot
├── scan_photos.py    # photo scanner — run via cron from home directory
├── setup.sh          # automated setup script for fresh Pi OS install
└── README.md

~/photos/             # SOURCE — drop your originals here (the Samba share)
├── photo_one.jpg
└── photo_two.jpg

/var/www/<hostname>.local/
├── index.html        # deployed slideshow page
├── photos.json       # auto-generated by scan_photos.py
└── photos/           # CACHE — pre-scaled copies served to the browser
    ├── photo_one.jpg
    └── photo_two.jpg

~/.slideshow_config                        # paths + scale resolution, written by setup.sh
~/.config/labwc/autostart                  # kiosk autostart (Pi OS Bookworm)
~/.config/lxsession/LXDE-pi/autostart     # kiosk autostart (older Pi OS)
```
