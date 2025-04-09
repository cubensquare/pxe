#!/bin/bash

# Script to prepare PXE server with customized Debian ISO from local path (e.g., pen drive copy)

set -euo pipefail
ISO_PATH="/root/custom-iso-download/debian-secure-v1.iso"
PXE_IP="172.16.4.58"
MNT_ISO="/mnt/iso"
TFTP_DIR="/srv/tftp/debian"
HTTP_LIVE_DIR="/var/www/html/debian/live"
PXE_CFG="/srv/tftp/pxelinux.cfg/default"

echo "======================================"
echo "[+] Validating environment and folders"
echo "======================================"

# Create mount and destination dirs
for dir in "$MNT_ISO" "$TFTP_DIR" "$HTTP_LIVE_DIR" "/srv/tftp/pxelinux.cfg"; do
    if [ ! -d "$dir" ]; then
        echo "  [+] Creating $dir"
        mkdir -p "$dir"
    else
        echo "  [✓] $dir already exists"
    fi
done

echo "======================================"
echo "[+] Mounting ISO: $ISO_PATH"
echo "======================================"

if [ ! -f "$ISO_PATH" ]; then
    echo "  [✗] ISO file not found: $ISO_PATH"
    exit 1
fi

# Unmount if already mounted
umount "$MNT_ISO" 2>/dev/null || true
mount -o loop "$ISO_PATH" "$MNT_ISO" || { echo "  [✗] Failed to mount ISO. Exiting."; exit 1; }

echo "======================================"
echo "[+] Copying boot files from ISO"
echo "======================================"

cp "$MNT_ISO/live/vmlinuz" "$TFTP_DIR/"
cp "$MNT_ISO/live/initrd.img" "$TFTP_DIR/"
cp "$MNT_ISO/live/filesystem.squashfs" "$HTTP_LIVE_DIR/"

echo "======================================"
echo "[+] Creating PXE boot menu"
echo "======================================"

cat <<EOF > "$PXE_CFG"
DEFAULT debian-secure
LABEL debian-secure
  MENU LABEL Debian Secure Live Boot
  KERNEL debian/vmlinuz
  APPEND initrd=debian/initrd.img boot=live fetch=http://$PXE_IP/debian/live/filesystem.squashfs
EOF

echo "======================================"
echo "[+] Restarting PXE services"
echo "======================================"

systemctl restart apache2
systemctl restart tftpd-hpa

echo "======================================"
echo "[+] Verifying copied files"
echo "======================================"

for f in vmlinuz initrd.img; do
    echo "  [>] $TFTP_DIR/$f"
    ls -lh "$TFTP_DIR/$f"
    file "$TFTP_DIR/$f"
    date -r "$TFTP_DIR/$f"
done

echo "  [>] $HTTP_LIVE_DIR/filesystem.squashfs"
ls -lh "$HTTP_LIVE_DIR/filesystem.squashfs"
file "$HTTP_LIVE_DIR/filesystem.squashfs"
date -r "$HTTP_LIVE_DIR/filesystem.squashfs"

echo "======================================"
echo "[✓] PXE setup complete. Boot PXE client in Legacy mode"
echo "======================================"
