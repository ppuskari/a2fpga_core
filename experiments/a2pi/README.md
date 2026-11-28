# A2PI phase 1: existing BL616 USB Ethernet host + Pi ECM gadget

Baseline: 673b4bb891dabd3a87385c641b3561153b985f70 (M3 latest development).
No FPGA, MCU, or Apple-side source changes in this phase.

## Supported hardware
Pi Zero 2 W preferred: micro-USB DATA port adjacent to mini-HDMI, not PWR IN.
Pi 4B alternative: USB-C OTG, with a properly engineered separate power/data arrangement.
Pi 3B+ does not expose USB peripheral mode; use a LAN connection with a supported
USB Ethernet adapter on A2FPGA instead. No need to buy another Pi.

Use the Enhanced external BL616 USB host port used for keyboard/gamepad.
Do not connect two independently powered 5 V rails together. For Zero 2 W,
use its proper separate supply and a verified VBUS-isolated USB data path
(D+, D-, GND maintained; USB enumeration may depend on VBUS sensing).
Do not use an ordinary dual-power cable. Verify board VBUS wiring first.
A properly designed powered hub can be evaluated separately; do not rely on
the Apple slot to power a Pi. Use a spare SD card.

## Setup
Install Raspberry Pi OS Lite using Imager, enable Wi-Fi and SSH, and leave
Imager's USB gadget option OFF because we need ECM only, not RNDIS.
SSH over Wi-Fi. Confirm model:
```sh
tr -d '\0' </proc/device-tree/model; echo
```
On current Raspberry Pi OS, add to /boot/firmware/config.txt under [all]:
```
dtoverlay=dwc2,dr_mode=peripheral
```
Remove conflicting otg_mode=1 settings where applicable (Pi 4), and any
g_ether autoload entry from cmdline.txt/modules or existing gadget service.
Do not otherwise alter the one-line cmdline. Reboot, then confirm
ls /sys/class/udc returns the controller. Copy phase1-ecm.sh to the Pi.
Install dnsmasq-base before connecting:
```sh
sudo apt update
sudo apt install dnsmasq-base
sudo sh phase1-ecm.sh
```
Run the dnsmasq command printed by the script in a second Wi-Fi SSH session.
This offers only 192.168.77.2, no default route or DNS; make sure
192.168.77.0/24 does not conflict with the Wi-Fi network. Script setup is
temporary and cleared by reboot. It assumes ECM kernel/configfs support
and a single available UDC. No production USB IDs are assigned.

## Test
1. Existing Enhanced card: keep DHCP ON in network settings. Boot the Pi
   and start the gadget and DHCP service before connecting USB.
2. With verified safe power/data arrangement, connect to the external
   BL616 USB host. Initially avoid hubs if possible.
3. Watch the HDMI MCU console. Existing main.c reports ETH IP after DHCP,
   or tg/sw/bn/rx/l counters while waiting. Expected address 192.168.77.2.
4. On Pi:
```sh
ip -br addr
ping -c 10 192.168.77.2
sudo apt install netcat-openbsd
nc -v 192.168.77.2 23
```
   The M3 telnetd should provide console text; c selects console, m selects
   menu, q exits. This is an unencrypted private bench link only.
   Do not expose these firmware services to the Internet.
5. If DHCP fails, record the status counters, dnsmasq output, and
   ip -s link. Optional static-IP test: DHCP OFF, IP 192.168.77.2,
   netmask 255.255.255.0, gateway 192.168.77.1 (no actual forwarding).
   Return to previous settings afterward.
6. Verify keyboard/hub coexistence separately. Current ECM RX is gated on a
   carrier notification and has a diagnostic data-toggle recovery; attach
   is not proof of data transfer. If detach/reattach fails, reboot the MCU
   rather than repeatedly exercising the unverified cleanup path.
7. Confirm MOD, SSI speech and Mockingboard remain unchanged. Record
   underruns, free heap, and USB errors. Do not enable streaming yet.

Acceptance: enumeration, DHCP or static address, successful bidirectional
ping and console exchange, no regression with Pi attached. Subsequent
phase: bounded TCP echo/throughput test with CRC and mixed audio workloads.
Target 192000 B/s for 48kHz S16 stereo, 384000 B/s minimum design headroom,
prefer >= 1 MB/s sustained if available. These are goals, not measurements.

Source inspection: firmware_host/main.c (CDC ECM and DHCP),
usb_config.h (EHCI and hubs), telnetd.c (TCP port 23).
Script has not been run on Pi hardware or this A2FPGA revision.
