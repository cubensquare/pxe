#!/bin/bash
# PXE Server Setup Script for Ubuntu 24.04.5 with Legacy BIOS + UEFI Support
# Author: CubenSquare
# Purpose: Setup PXE Server with TFTP, DHCP, NFS and Debian ISO (Legacy & UEFI)

set -e

# === 0. PXE Server Configuration ===
PXE_IP="172.16.4.58"
PXE_GATEWAY="172.16.4.1"
PXE_NET="172.16.4.0"
PXE_NETMASK="255.255.255.0"
PXE_RANGE_START="172.16.4.100"
PXE_RANGE_END="172.16.4.200"

# === 1. Check Internet ===
echo "[+] Validating internet connectivity"
if ping -c 2 8.8.8.8 >/dev/null; then
  echo "Internet is working."
else
  echo " Internet not reachable. Please fix your connection and try again."
  exit 1
fi

# === 2. Configure Static IP ===
INTERFACE="$(ip -o -4 route show to default | awk '{print $5}' | head -1)"
NETPLAN_FILE="/etc/netplan/00-pxe.yaml"

echo "[+] Setting static IP address for PXE Server"
if [ ! -f "$NETPLAN_FILE" ]; then
cat <<EOF | tee $NETPLAN_FILE
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses: [${PXE_IP}/24]
      gateway4: $PXE_GATEWAY
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF
  netplan apply
  echo " Static IP configured as $PXE_IP on $INTERFACE"
else
  echo " Netplan config already exists. Skipping static IP setup."
fi

# === 3. Install required packages ===
echo "[+] Installing required packages"
apt update
apt install -y isc-dhcp-server tftpd-hpa nfs-kernel-server apache2 syslinux-common pxelinux isolinux wget curl xorriso grub-efi-amd64-bin

# === 4. Configure DHCP ===
echo "[+] Configuring DHCP server"
DHCP_CONF="/etc/dhcp/dhcpd.conf"
if ! grep -q "pxelinux.0" $DHCP_CONF; then
cat <<EOF | tee $DHCP_CONF
option domain-name "pxe.local";
option domain-name-servers 8.8.8.8;
default-lease-time 600;
max-lease-time 7200;
log-facility local7;

subnet $PXE_NET netmask $PXE_NETMASK {
  range $PXE_RANGE_START $PXE_RANGE_END;
  option routers $PXE_GATEWAY;
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
  echo " DHCP configuration created."
else
  echo " DHCP config already exists. Skipping."
fi

systemctl enable isc-dhcp-server
systemctl restart isc-dhcp-server

# === 5. Configure TFTP ===
echo "[+] Configuring TFTP server"
mkdir -p /srv/tftp/pxelinux.cfg /srv/tftp/EFI/BOOT
cp -u /usr/lib/PXELINUX/pxelinux.0 /srv/tftp/
cp -u /usr/lib/syslinux/modules/bios/{ldlinux.c32,menu.c32,libcom32.c32,libutil.c32} /srv/tftp/
cp -u /usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed /srv/tftp/EFI/BOOT/

# === 6. Create PXE BIOS Menu ===
PXE_MENU="/srv/tftp/pxelinux.cfg/default"
if [ ! -f "$PXE_MENU" ]; then
cat <<EOF | tee $PXE_MENU
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
  echo " PXE BIOS menu created."
else
  echo " PXE BIOS menu already exists."
fi

# === 7. Create GRUB config for UEFI ===
GRUB_CFG="/srv/tftp/boot/grub/grub.cfg"
mkdir -p /srv/tftp/boot/grub
cat <<EOF | tee $GRUB_CFG
set timeout=5
set default=0

menuentry "Debian Live XFCE" {
  linux /debian/vmlinuz boot=live components username=user noswap noeject fetch=http://$PXE_IP/debian/live/filesystem.squashfs
  initrd /debian/initrd.img
}
EOF

# === 8. Configure TFTP server path ===
cat <<EOF | tee /etc/default/tftpd-hpa
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"
EOF

systemctl restart tftpd-hpa

# === 9. Download Debian ISO ===
echo "[+] Downloading Debian Live ISO (XFCE 12.5.0)"
mkdir -p /mnt/iso /var/www/html/debian/live /srv/tftp/debian
if [ ! -f "~/debian.iso" ]; then
  wget -O ~/debian.iso https://cdimage.debian.org/cdimage/archive/12.5.0-live/amd64/iso-hybrid/debian-live-12.5.0-amd64-xfce.iso
else
  echo " Debian ISO already downloaded. Skipping."
fi

# === 10. Mount and Extract ISO ===
echo "[+] Mounting and extracting ISO contents"
mount -o loop ~/debian.iso /mnt/iso
cp -u /mnt/iso/live/initrd.img /srv/tftp/debian/
cp -u /mnt/iso/live/vmlinuz /srv/tftp/debian/
cp -u /mnt/iso/live/filesystem.squashfs /var/www/html/debian/live/
umount /mnt/iso

# === 11. Configure NFS ===
if ! grep -q "/var/www/html/debian" /etc/exports; then
cat <<EOF | tee -a /etc/exports
/var/www/html/debian *(ro,sync,no_subtree_check)
EOF
  exportfs -ra
  echo " NFS export added."
else
  echo " NFS export already exists."
fi

systemctl restart nfs-kernel-server

# === 12. Restart Apache ===
systemctl restart apache2

# === 13. Done ===
echo " PXE Server setup complete. BIOS & UEFI clients can now boot Debian Live from network."
echo " PXE Server IP: $PXE_IP | Interface: $INTERFACE"
echo " Clients should be set to Network Boot (Legacy BIOS or UEFI)"
