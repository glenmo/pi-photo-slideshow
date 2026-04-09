#!/bin/bash
# =============================================================================
# Pi Photo Slideshow — Automated Setup Script
# https://github.com/glenmo/pi-photo-slideshow
#
# Tested on: Raspberry Pi 3 & 5, Raspberry Pi OS (Debian Bookworm)
# Run as your normal user (not root) — sudo is used internally where needed
# =============================================================================

set -e  # exit on any error

# --- Colour output helpers ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # no colour

info()    { echo -e "${CYAN}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}  Pi Photo Slideshow — Setup Script   ${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# =============================================================================
# Configuration — edit these if needed
# =============================================================================
HOSTNAME="$(hostname)"
DOMAIN="${HOSTNAME}.local"
DOCROOT="/var/www/${DOMAIN}"
PHOTOS_DIR="${DOCROOT}/photos"
VHOST_CONF="/etc/apache2/sites-available/${DOMAIN}.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER="$(whoami)"

info "Setting up for user: ${USER}"
info "Hostname: ${HOSTNAME}"
info "Domain: http://${DOMAIN}/"
info "Document root: ${DOCROOT}"
echo ""

# =============================================================================
# 1. System update and package install
# =============================================================================
info "Updating package lists..."
sudo apt-get update -q

info "Installing Apache2, Python3, and Samba..."
sudo apt-get install -y -q apache2 python3 samba

success "Packages installed."
echo ""

# =============================================================================
# 2. Apache2 virtual host setup
# =============================================================================
info "Creating document root at ${DOCROOT}..."
sudo mkdir -p "${PHOTOS_DIR}"
sudo chown -R "${USER}:www-data" "${DOCROOT}"
sudo chmod -R 775 "${DOCROOT}"

info "Writing Apache2 virtual host config..."
sudo tee "${VHOST_CONF}" > /dev/null << APACHECONF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}
    DocumentRoot ${DOCROOT}
    <Directory ${DOCROOT}>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined
</VirtualHost>
APACHECONF

info "Enabling virtual host..."
sudo a2ensite "${DOMAIN}.conf" > /dev/null 2>&1
sudo systemctl reload apache2

success "Apache2 configured at http://${DOMAIN}/"
echo ""

# =============================================================================
# 3. Deploy slideshow files
# =============================================================================
info "Deploying index.html to document root..."
if [ -f "${SCRIPT_DIR}/index.html" ]; then
    sudo cp "${SCRIPT_DIR}/index.html" "${DOCROOT}/index.html"
    sudo chown "${USER}:www-data" "${DOCROOT}/index.html"
    success "index.html deployed."
else
    error "index.html not found in ${SCRIPT_DIR}. Make sure you run this script from the repo folder."
fi

info "Installing scan_photos.py to home directory..."
if [ -f "${SCRIPT_DIR}/scan_photos.py" ]; then
    cp "${SCRIPT_DIR}/scan_photos.py" "${HOME}/scan_photos.py"
    chmod +x "${HOME}/scan_photos.py"
    success "scan_photos.py installed to ${HOME}/scan_photos.py"
else
    error "scan_photos.py not found in ${SCRIPT_DIR}. Make sure you run this script from the repo folder."
fi

echo ""

# =============================================================================
# 4. Run scanner once to create photos.json
# =============================================================================
info "Running photo scanner..."
python3 "${HOME}/scan_photos.py"
success "photos.json created."
echo ""

# =============================================================================
# 5. Cron job
# =============================================================================
info "Setting up cron job (runs every minute)..."
CRON_JOB="* * * * * python3 ${HOME}/scan_photos.py"
# Add only if not already present
( crontab -l 2>/dev/null | grep -qF "scan_photos.py" ) \
    && warn "Cron job already exists, skipping." \
    || ( crontab -l 2>/dev/null; echo "${CRON_JOB}" ) | crontab -
success "Cron job set."
echo ""

# =============================================================================
# 6. Samba share for drag-and-drop from Mac/PC
# =============================================================================
info "Configuring Samba share for photos folder..."

# Check if share already exists
if sudo grep -q "\[photos\]" /etc/samba/smb.conf 2>/dev/null; then
    warn "Samba [photos] share already exists, skipping."
else
    sudo tee -a /etc/samba/smb.conf > /dev/null << SAMBACONF

[photos]
   path = ${PHOTOS_DIR}
   browseable = yes
   read only = no
   guest ok = no
   create mask = 0644
   directory mask = 0755
   force user = ${USER}
SAMBACONF
    sudo systemctl restart smbd
    success "Samba share configured."
fi

echo ""
warn "You still need to set a Samba password to access the share:"
echo -e "      ${YELLOW}sudo smbpasswd -a ${USER}${NC}"
echo -e "      Then connect from Mac Finder with: ${YELLOW}smb://${DOMAIN}/photos${NC}"
echo ""

# =============================================================================
# 7. Kiosk autostart
# =============================================================================
info "Setting up Chromium kiosk mode on boot..."
AUTOSTART_DIR="${HOME}/.config/lxsession/LXDE-pi"
AUTOSTART_FILE="${AUTOSTART_DIR}/autostart"

mkdir -p "${AUTOSTART_DIR}"

# Check if already configured
if grep -q "chromium-browser --kiosk" "${AUTOSTART_FILE}" 2>/dev/null; then
    warn "Kiosk autostart already configured, skipping."
else
    cat >> "${AUTOSTART_FILE}" << AUTOSTART

@xset s off
@xset -dpms
@xset s noblank
@chromium-browser --kiosk --incognito --disable-restore-session-state http://${DOMAIN}
AUTOSTART
    success "Kiosk autostart configured."
fi

echo ""

# =============================================================================
# 8. Pi 3 performance tweaks
# =============================================================================
info "Applying Pi 3 performance tweaks..."

# Increase GPU memory split for smoother display
GPU_MEM=$(grep "gpu_mem" /boot/firmware/config.txt 2>/dev/null || grep "gpu_mem" /boot/config.txt 2>/dev/null || echo "")
CONFIG_FILE="/boot/firmware/config.txt"
[ -f "${CONFIG_FILE}" ] || CONFIG_FILE="/boot/config.txt"

if echo "${GPU_MEM}" | grep -q "gpu_mem"; then
    warn "gpu_mem already set in ${CONFIG_FILE}, skipping."
else
    echo "gpu_mem=128" | sudo tee -a "${CONFIG_FILE}" > /dev/null
    success "Set gpu_mem=128 for smoother display rendering."
fi

echo ""

# =============================================================================
# Done
# =============================================================================
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}  Setup complete!                     ${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo -e "  Slideshow URL : ${CYAN}http://${DOMAIN}/${NC}"
echo -e "  Photos folder : ${CYAN}${PHOTOS_DIR}${NC}"
echo -e "  Add photos via: ${CYAN}scp photo.jpg ${USER}@${DOMAIN}:${PHOTOS_DIR}/${NC}"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo -e "  1. Set Samba password:  ${YELLOW}sudo smbpasswd -a ${USER}${NC}"
echo -e "  2. Add some photos to:  ${YELLOW}${PHOTOS_DIR}${NC}"
echo -e "  3. Reboot to start kiosk: ${YELLOW}sudo reboot${NC}"
echo ""
