#!/bin/bash
# Use this script to download the customized ISO from a pendrive to pxe server and process the same, so the downloaded customized iso can be used to boot the pxe client

set -e

PXE_IP="172.16.4.58"
ISO_PATH="/root/iso-download/debian-secure-v1.iso"

echo "[+] Mounting ISO..."
mkdir -p /mnt/iso
mount -o loop "$ISO_PATH" /mnt/iso

echo "[+] Copying boot files..."
mkdir -p /srv/tftp/debian
mkdir -p /var/www/html/debian/live
cp /mnt/iso/live/vmlinuz /srv/tftp/debian/
cp /mnt/iso/live/initrd.img /srv/tftp/debian/
cp /mnt/iso/live/filesystem.squashfs /var/www/html/debian/live/

echo "[+] Creating PXE boot menu..."
mkdir -p /srv/tftp/pxelinux.cfg
cat <<EOF > /srv/tftp/pxelinux.cfg/default
DEFAULT debian-secure
LABEL debian-secure
  KERNEL debian/vmlinuz
  INITRD debian/initrd.img
  APPEND boot=live fetch=http://$PXE_IP/debian/live/filesystem.squashfs
EOF

echo "[+] Restarting PXE services..."
systemctl restart apache2
systemctl restart tftpd-hpa

echo "[✓] PXE server is ready. Boot PXE client in Legacy mode."
