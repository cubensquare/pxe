#!/bin/bash

# PXE ISO Setup Script (Improved)
set -e

PXE_IP="172.16.4.58"
ISO_PATH="/root/custom-iso-download/debian-secure-v1.iso"
ISO_MOUNT="/mnt/iso"
TFTP_DIR="/srv/tftp/debian"
HTTP_DIR="/var/www/html/debian/live"
PXE_MENU="/srv/tftp/pxelinux.cfg/default"

echo "[+] Validating ISO path..."
if [ ! -f "$ISO_PATH" ]; then
  echo "❌ ISO not found at $ISO_PATH"
  exit 1
fi

echo "[+] Cleaning existing mount (if any)..."
if mountpoint -q "$ISO_MOUNT"; then
  umount "$ISO_MOUNT"
  sleep 1
fi
mkdir -p "$ISO_MOUNT"

echo "[+] Mounting ISO..."
mount -o loop "$ISO_PATH" "$ISO_MOUNT"
sleep 2

echo "[+] Preparing PXE directories..."
mkdir -p "$TFTP_DIR" "$HTTP_DIR" "/srv/tftp/pxelinux.cfg"

echo "[+] Copying boot files..."
cp "$ISO_MOUNT/live/vmlinuz" "$TFTP_DIR/"
cp "$ISO_MOUNT/live/initrd.img" "$TFTP_DIR/"
cp "$ISO_MOUNT/live/filesystem.squashfs" "$HTTP_DIR/"
sleep 2

echo "[+] Creating PXE boot menu..."
cat <<EOF > "$PXE_MENU"
DEFAULT debian-secure
LABEL debian-secure
  KERNEL debian/vmlinuz
  INITRD debian/initrd.img
  APPEND boot=live fetch=http://$PXE_IP/debian/live/filesystem.squashfs
EOF
sleep 1

echo "[+] Restarting PXE services..."
systemctl restart apache2
sleep 2
systemctl restart tftpd-hpa
sleep 2

echo "[+] Final Validations:"
echo "----------------------------------------"
echo "[✓] Mounted ISO contents:"
ls -lh "$ISO_MOUNT/live/"

echo "----------------------------------------"
echo "[✓] PXE Boot Menu:"
cat "$PXE_MENU"

echo "----------------------------------------"
echo "[✓] Boot files in TFTP directory:"
ls -lh "$TFTP_DIR"

echo "----------------------------------------"
echo "[✓] Filesystem.squashfs in HTTP directory:"
ls -lh "$HTTP_DIR"

echo "----------------------------------------"
echo "[✅] PXE server is ready. Boot PXE client in Legacy mode."
