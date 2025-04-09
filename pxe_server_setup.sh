#!/bin/bash

set -e

ISO_PATH="/root/custom-iso-download/debian-secure-v1.iso"
PXE_IP="172.16.4.58"
MOUNT_DIR="/mnt/iso"
TFTP_DIR="/srv/tftp/debian"
HTTP_DIR="/var/www/html/debian/live"
PXELINUX_CFG="/srv/tftp/pxelinux.cfg/default"

echo -e "\n\033[1;34m[+] Validating ISO path...\033[0m"
if [[ ! -f "$ISO_PATH" ]]; then
  echo -e "\033[1;31m[✗] ISO file not found: $ISO_PATH\033[0m"
  exit 1
fi

echo -e "\033[1;34m[+] Cleaning mount point...\033[0m"
umount "$MOUNT_DIR" 2>/dev/null || true
rm -rf "$MOUNT_DIR"
mkdir -p "$MOUNT_DIR"
sleep 1

echo -e "\033[1;34m[+] Mounting ISO...\033[0m"
if ! mount -o loop "$ISO_PATH" "$MOUNT_DIR"; then
  echo -e "\033[1;31m[✗] Failed to mount ISO\033[0m"
  exit 1
fi
sleep 2

echo -e "\033[1;34m[+] Validating kernel & initrd files...\033[0m"
for f in vmlinuz initrd.img; do
  if [[ ! -f "$MOUNT_DIR/live/$f" ]]; then
    echo -e "\033[1;31m[✗] $f not found in ISO\033[0m"
    exit 1
  fi
  TYPE=$(file "$MOUNT_DIR/live/$f")
  echo "  $f => $TYPE"
  if [[ "$TYPE" == *"data"* ]]; then
    echo -e "\033[1;31m[✗] $f is corrupted or not a valid kernel/initrd image\033[0m"
    exit 1
  fi
done

echo -e "\033[1;34m[+] Preparing PXE directories...\033[0m"
mkdir -p "$TFTP_DIR" "$HTTP_DIR"
sleep 1

echo -e "\033[1;34m[+] Copying files...\033[0m"
cp "$MOUNT_DIR/live/vmlinuz" "$TFTP_DIR/"
cp "$MOUNT_DIR/live/initrd.img" "$TFTP_DIR/"
cp "$MOUNT_DIR/live/filesystem.squashfs" "$HTTP_DIR/"
sleep 1

echo -e "\033[1;34m[+] Updating PXE boot menu...\033[0m"
mkdir -p "$(dirname "$PXELINUX_CFG")"
cat <<EOF > "$PXELINUX_CFG"
DEFAULT debian-secure
LABEL debian-secure
  KERNEL debian/vmlinuz
  INITRD debian/initrd.img
  APPEND boot=live fetch=http://$PXE_IP/debian/live/filesystem.squashfs
EOF
sleep 1

echo -e "\033[1;34m[+] Restarting PXE services...\033[0m"
systemctl restart apache2
systemctl restart tftpd-hpa
sleep 2

echo -e "\n\033[1;32m[✓] PXE server is ready. Boot PXE client in Legacy mode.\033[0m"
