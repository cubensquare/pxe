#!/bin/bash
# PXE Server Setup Script - BIOS Only (Legacy Boot)
# Author: CubenSquare
# For Debian Live PXE Boot (Only Legacy BIOS supported)

set -e

# === PXE Network Config ===
PXE_IP="172.16.4.58"
PXE_GATEWAY="172.16.4.1"
PXE_NET="172.16.4.0"
PXE_NETMASK="255.255.255.0"
PXE_RANGE_START="172.16.4.100"
PXE_RANGE_END="172.16.4.200"

# === 1. Check Internet ===
echo "[+] Checking internet connection"
ping -c 2 8.8.8.8 >/dev/null || { echo "Internet not reachable. Exiting."; exit 1; }

# === 2. Configure Static IP ===
INTERFACE="$(ip -o -4 route show to default | awk '{print $5}' | head -1)"
NETPLAN_FILE="/etc/netplan/00-pxe.yaml"

echo "[+] Setting static IP for PXE server"
if [ -f "$NETPLAN_FILE" ]; then
  echo "[!] Existing Netplan file found. Replacing..."
  rm -f "$NETPLAN_FILE"
fi

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
echo " Static IP set to $PXE_IP"

# === 3. Install packages ===
echo "[+] Installing PXE components"
apt update
apt install -y isc-dhcp-server tftpd-hpa apache2 nfs-kernel-server syslinux-common pxelinux wget

# === 4. DHCP Config (Legacy BIOS Only) ===
DHCP_CONF="/etc/dhcp/dhcpd.conf"
if [ -f "$DHCP_CONF" ]; then
  echo "[!] Removing existing $DHCP_CONF"
  rm -f "$DHCP_CONF"
fi

cat <<EOF | tee $DHCP_CONF
option domain-name "pxe.local";
option domain-name-servers 8.8.8.8;
default-lease-time 600;
max-lease-time 7200;
log-facility local7;

subnet $PXE_NET netmask $PXE_NETMASK {
  range $PXE_RANGE_START $PXE_RANGE_END;
  option routers $PXE_GATEWAY;
  filename "pxelinux.0";
  next-server $PXE_IP;
}
EOF

ISC_DEFAULT="/etc/default/isc-dhcp-server"
if [ -f "$ISC_DEFAULT" ]; then
  echo "[!] Removing existing $ISC_DEFAULT"
  rm -f "$ISC_DEFAULT"
fi

echo "INTERFACESv4=\"$INTERFACE\"" | tee $ISC_DEFAULT

systemctl enable isc-dhcp-server
systemctl restart isc-dhcp-server

# === 5. TFTP Setup ===
echo "[+] Setting up TFTP server"
mkdir -p /srv/tftp/pxelinux.cfg /srv/tftp/debian
cp -u /usr/lib/PXELINUX/pxelinux.0 /srv/tftp/
cp -u /usr/lib/syslinux/modules/bios/{ldlinux.c32,menu.c32,libcom32.c32,libutil.c32} /srv/tftp/

# === 6. Create PXE Boot Menu ===
PXE_MENU="/srv/tftp/pxelinux.cfg/default"
if [ -f "$PXE_MENU" ]; then
  echo "[!] Removing existing PXE menu"
  rm -f "$PXE_MENU"
fi

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

# === 7. Configure TFTP Service ===
TFTP_CONF="/etc/default/tftpd-hpa"
if [ -f "$TFTP_CONF" ]; then
  echo "[!] Replacing $TFTP_CONF"
  rm -f "$TFTP_CONF"
fi

cat <<EOF | tee $TFTP_CONF
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"
EOF

systemctl restart tftpd-hpa

# === 8. Download Debian ISO (Live Standard) ===
echo "[+] Downloading Debian Live ISO"
mkdir -p /mnt/iso /var/www/html/debian/live
if [ ! -f ~/debian.iso ]; then
  wget -O ~/debian.iso https://cdimage.debian.org/cdimage/archive/12.5.0-live/amd64/iso-hybrid/debian-live-12.5.0-amd64-xfce.iso
else
  echo " Debian ISO already exists at ~/debian.iso"
fi

# === 9. Mount and Extract Boot Files ===
mount -o loop ~/debian.iso /mnt/iso
cp -u /mnt/iso/live/initrd.img /srv/tftp/debian/
cp -u /mnt/iso/live/vmlinuz /srv/tftp/debian/
cp -u /mnt/iso/live/filesystem.squashfs /var/www/html/debian/live/
umount /mnt/iso

# === 10. NFS Export (Optional) ===
if ! grep -q "/var/www/html/debian" /etc/exports; then
echo "/var/www/html/debian *(ro,sync,no_subtree_check)" >> /etc/exports
exportfs -ra
fi

systemctl restart nfs-kernel-server
systemctl restart apache2

# === 11. Done ===
echo "✅ PXE Server setup complete (Legacy BIOS only)"
echo "📡 PXE IP: $PXE_IP | Interface: $INTERFACE"
echo "🖥️ Client must be in Legacy/BIOS boot mode"
