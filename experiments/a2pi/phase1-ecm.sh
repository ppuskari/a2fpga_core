#!/bin/sh
# A2PI lab-only ECM gadget. Run as root on a Pi with dwc2 peripheral mode.
# Does not install a boot service, route traffic, or change the Apple firmware.
set -eu
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }
modprobe libcomposite
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
root=/sys/kernel/config/usb_gadget
g=$root/a2pi
[ ! -e "$g" ] || { echo "a2pi already exists; reboot before rerunning"; exit 1; }
[ ! -d /sys/module/g_ether ] || { echo "Disable g_ether first"; exit 1; }
set -- /sys/class/udc/*
[ -e "$1" ] && [ "$#" = 1 ] || { echo "Expected one USB device controller; check dwc2 peripheral overlay"; exit 1; }
udc=${1##*/}
for f in "$root"/*/UDC; do
    [ -f "$f" ] || continue
    [ -z "$(cat "$f")" ] || { echo "Another USB gadget is bound"; exit 1; }
done
mkdir "$g"
cd "$g"
# Linux composite example identifiers, for local experimentation only.
echo 0x1d6b > idVendor
echo 0x0104 > idProduct
echo 0x0200 > bcdUSB
mkdir strings/0x409
echo A2PI-LAB-01 > strings/0x409/serialnumber
echo A2PI-LAB > strings/0x409/manufacturer
echo 'A2PI ECM prototype' > strings/0x409/product
mkdir configs/c.1
mkdir configs/c.1/strings/0x409
echo ECM > configs/c.1/strings/0x409/configuration
# Experiment assumes a self-powered Pi and protected VBUS path.
echo 0xc0 > configs/c.1/bmAttributes
echo 2 > configs/c.1/MaxPower
mkdir functions/ecm.usb0
echo 02:41:32:50:49:01 > functions/ecm.usb0/dev_addr
echo 02:41:32:50:49:02 > functions/ecm.usb0/host_addr
ln -s functions/ecm.usb0 configs/c.1/
echo "$udc" > UDC
iface=$(cat functions/ecm.usb0/ifname)
if command -v nmcli >/dev/null 2>&1; then
    nmcli device set "$iface" managed no
fi
ip addr replace 192.168.77.1/24 dev "$iface"
ip link set "$iface" up
echo "ECM interface: $iface (192.168.77.1/24)"
echo "For DHCP in a second terminal:"
echo "sudo dnsmasq --no-daemon --port=0 --interface=$iface --bind-interfaces --dhcp-range=192.168.77.2,192.168.77.2,255.255.255.0,1h --dhcp-option=3 --dhcp-option=6 --log-dhcp"
