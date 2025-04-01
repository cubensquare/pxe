#!/bin/bash
# PXE Server Setup Script for Ubuntu 24.04.5 with Legacy BIOS + UEFI Support
# Author: CubenSquare
# Purpose: Setup PXE Server with TFTP, DHCP, NFS and Debian ISO (Legacy & UEFI)

set -e

# === 0. Check Internet ===
echo "[+] Validating internet connectivity"
if ping -c 2 8.8.8.8 >/dev/null; then
  echo "✅ Internet is working."
else
  echo "❌ Internet not reachable. Please fix your connection and try again."
  exit 1
fi

# === 1. Configure Static IP (Optional) ===
PXE_IP="192.168.68.101"
INTERFACE="$(ip -o -4 route show to default | awk '{print $5}' | head -1)"
NETPLAN_FILE="/etc/netplan/00-pxe.yaml"

echo "[+] Setting static IP address for PXE Server"
if [ ! -f "$NETPLAN_FILE" ]; then
cat <<EOF | sudo tee $NETPLAN_FILE
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses: [${PXE_IP}/24]
      gateway4: 192.168.68.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF
  sudo netplan apply
  echo "✅ Static IP configured as $PXE_IP on $INTERFACE"
else
  echo "ℹ️ Netplan config already exists. Skipping static IP setup."
fi

# === 2. Install required packages ===
echo "[+] Installing required packages"
sudo apt update
sudo apt install -y isc-dhcp-server tftpd-hpa nfs-kernel-server apache2 syslinux-common pxelinux isolinux wget curl xorriso grub-efi-amd64-bin

# === 3. Configure DHCP ===
echo "[+] Configuring DHCP server"
DHCP_CONF="/etc/dhcp/dhcpd.conf"
if ! grep -q "pxelinux.0" $DHCP_CONF; then
cat <<EOF | sudo tee $DHCP_CONF
option domain-name "pxe.local";
option domain-name-servers 8.8.8.8;
default-lease-time 600;
max-lease-time 7200;
log-facility local7;

subnet 192.168.68.0 netmask 255.255.255.0 {
  range 192.168.68.150 192.168.68.200;
  option routers 192.168.68.1;
  if exists user-class and option user-class = "iPXE" {
    filename "http://$PXE_IP/ipxe.efi";
  } else if option arch = 00:07 {
    filename "grubnetx64.efi.signed";
  } else {
    filename "pxelinux.0";
  }
  next-server $PXE_IP;
}
EOF
  echo "✅ DHCP configuration created."
else
  echo "ℹ️ DHCP config already exists. Skipping."
fi

sudo systemctl enable isc-dhcp-server
sudo systemctl restart isc-dhcp-server

# === 4. Configure TFTP ===
echo "[+] Configuring TFTP server"
sudo mkdir -p /srv/tftp/pxelinux.cfg /srv/tftp/EFI/BOOT
cp -u /usr/lib/PXELINUX/pxelinux.0 /srv/tftp/
cp -u /usr/lib/syslinux/modules/bios/{ldlinux.c32,menu.c32,libcom32.c32,libutil.c32} /srv/tftp/

# Copy GRUB EFI binary
cp -u /usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed /srv/tftp/EFI/BOOT/

# Create PXE (BIOS) Menu
PXE_MENU="/srv/tftp/pxelinux.cfg/default"
if [ ! -f "$PXE_MENU" ]; then
cat <<EOF | sudo tee $PXE_MENU
DEFAULT menu.c32
PROMPT 0
TIMEOUT 50
ONTIMEOUT Debian

MENU TITLE PXE Boot Menu

LABEL Debian
  MENU LABEL Boot Debian Live XFCE
  KERNEL debian/vmlinuz
  APPEND initrd=debian/initrd.img boot=live components username=user noswap noeject fetch=http://$PXE_IP/debian/live/filesystem.squashfs
EOF
  echo "✅ PXE BIOS menu created."
else
  echo "ℹ️ PXE BIOS menu already exists."
fi

# Create GRUB config for UEFI
GRUB_CFG="/srv/tftp/boot/grub/grub.cfg"
sudo mkdir -p /srv/tftp/boot/grub
cat <<EOF | sudo tee $GRUB_CFG
set timeout=5
set default=0

menuentry "Debian Live XFCE" {
  linux /debian/vmlinuz boot=live components username=user noswap noeject fetch=http://$PXE_IP/debian/live/filesystem.squashfs
  initrd /debian/initrd.img
}
EOF

# === 5. Configure TFTP server path ===
cat <<EOF | sudo tee /etc/default/tftpd-hpa
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"
EOF

sudo systemctl restart tftpd-hpa

# === 6. Download Debian ISO ===
echo "[+] Downloading Debian Live ISO (XFCE 12.5.0)"
sudo mkdir -p /mnt/iso /var/www/html/debian/live /srv/tftp/debian
if [ ! -f "~/debian.iso" ]; then
  wget -O ~/debian.iso https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/debian-live-12.5.0-amd64-xfce.iso
else
  echo "ℹ️ Debian ISO already downloaded. Skipping."
fi

# === 7. Mount and Extract ISO ===
echo "[+] Mounting and extracting ISO contents"
sudo mount -o loop ~/debian.iso /mnt/iso
cp -u /mnt/iso/live/initrd.img /srv/tftp/debian/
cp -u /mnt/iso/live/vmlinuz /srv/tftp/debian/
cp -u /mnt/iso/live/filesystem.squashfs /var/www/html/debian/live/
sudo umount /mnt/iso

# === 8. Configure NFS for additional use ===
if ! grep -q "/var/www/html/debian" /etc/exports; then
cat <<EOF | sudo tee -a /etc/exports
/var/www/html/debian *(ro,sync,no_subtree_check)
EOF
  sudo exportfs -ra
  echo "✅ NFS export added."
else
  echo "ℹ️ NFS export already exists."
fi

sudo systemctl restart nfs-kernel-server

# === 9. Restart Apache ===
sudo systemctl restart apache2

# === 10. Done ===
echo "✅ PXE Server setup complete. BIOS & UEFI clients can now boot Debian Live from network."
echo "➡️ PXE Server IP: $PXE_IP | Interface: $INTERFACE"
echo "➡️ Clients should be set to Network Boot (Legacy BIOS or UEFI)"
