# P10-R3 — USB HID menu, 15-second handoff, and USB SCSI diagnostics

**Development branch:** `petar/ssi263-p10r3-usb-host-ui-20261109`  
**Base:** known Gowin timing-closed `petar/ssi263-p10-hybrid-feasibility-20261109`.

## Hardware finding

The 2026-11-09 photo confirms the P10 BL616 firmware executed,
successfully spoke to the FPGA transport status registers, and
launched its Pico-C hybrid task:

```
P10 SSI263: PICO-C HYBRID ONLINE
P10 SPEECH BLOCKS=0 SLOW=0 SEQGAP=0
DISK II: USB MOUNT FAILED (FR=1)
DISK II: USB 0 BLK X 0 B
A2: RESET RELEASED (NO MEDIA)
```

The code reports 0 speech blocks until an Apple II program actually
writes an SSI phoneme. This is not a speech-fidelity test.

Two independent MCU/UI issues were found in source:

1. The `disk_remount()` failure and no-media paths never armed the
   `g_hide_console_at_us` deadline. The **FPGA reset-release
   backstop** is independent, so the Apple II may already be running
   behind the MCU console permanently.
2. The USB host firmware ran only `usbh_xinput` for menu buttons;
   `CONFIG_CHERRYUSB_HOST_HID` and a keyboard report consumer were
   missing. Pressing USB TAB therefore did nothing.

A third (separate) issue is the USB mass storage SCSI device returned
zero geometry, which makes FatFS fail with `FR_DISK_ERR=1`. The USB
class *attached* but that did not establish successful block reads.
The new geometry log reports block count and size immediately after
`usbh_msc_scsi_init()`. Do not assume reformatting is the sole fix
when the drive reports **0 blocks of 0 bytes**.

## P10-R3 changes

- `firmware_host/disk.c` arms a nonblocking **15-second console
  timeout** on every mount attempt, including all early returns and
  no-media cases. On successful image mount it shortens the
  deadline to the existing **1.5 seconds**. Repeated `P10 SPEECH`
  status log lines will not force the console visible again.
- `firmware_host/proj.conf` enables **CherryUSB 1.5.3 HID host**
  along with existing USB mass storage, Ethernet and XInput.
- `firmware_host/usb_kbd_menu.[ch]` handles **USB boot keyboard**
  reports with the stock CherryUSB HID callbacks. Keyboard IRQs only
  queue events; the existing 20 ms `xinput_thread` handles all menu
  operations and SPI, avoiding the known interrupt-mutex deadlock.
- Key controls: **TAB opens menu** from any view; **arrows navigate**
  and adjust choices; **Enter activates**; **Esc/Backspace go back**
  (at root returns to Apple); **Y switches console/menu**.
  Keys are rising-edge triggered; Apple II keyboard passthrough is
  not emulated by the MCU HID handler.
- `firmware_host/main.c` logs USB MSC SCSI block count/size and
  reports when geometry is unavailable, then retains the old remount
  behavior. This avoids guessing why `FR=1` occurred.
- `ssi263_hybrid.c`, `ssi263_hybrid_bridge.sv`, P10 speech bus,
  native DOC piano, AY effects, full IIgs video and FPGA RTL are
  untouched.

## Validation

- New GitHub Actions workflow:
  `.github/workflows/ssi263-p10r3-usb-host-ui.yml`.
- Host C stubs test USB boot keyboard TAB, Enter, ESC, arrows, Y,
  held-key suppression and disconnect clearing.
- Structural checks confirm USB HID *and* MSC enabled and both
  XInput menu paths continue to pump HID input.
- **The actual Windows Bouffalo SDK v2.3.27 BL616 build, USB HID
  enumeration and menu interaction on hardware remain untested.**
- **Do not re-flash FPGA.** Keep the successful P10-R2 bitstream.
- Keep the last known-good Stage 2 binary before uploading R3.
- Existing firmware flashing procedure MUST be **Stage 2 only at
  address 0x40000**; preserve the secure boot/Stage 1 at 0x0.

## One-line PowerShell 5.1 commands

From the existing P10 checkout:

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10
```

```powershell
git fetch origin
```

```powershell
git switch --track origin/petar/ssi263-p10r3-usb-host-ui-20261109
```

```powershell
Set-Location .\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
```

```powershell
make -j4
```

```powershell
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin
```

If successful, backup your previous Stage2 binary. Then from the
`a2n20_bl616` parent directory use:

```powershell
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

The programmer's readback verification currently has a known
`flash.bin` location issue: success of flashing does not itself
establish a byte-for-byte readback match.

**Do not switch branches with uncommitted changes you need to keep.**
All modifications are confined to firmware_host files and tests;
Gowin rerun is unnecessary.

## Hardware acceptance

1. P10 BL616 boot console still displays `P10 SSI263 ... ONLINE`.
2. A USB boot keyboard connected to the **BL616 USB-host side**
   enumerates and logs `USB KBD: TAB OPENS MENU`. Use a suitable
   powered USB hub if simultaneous thumb drive and keyboard are needed.
3. TAB opens the menu; arrow keys/Enter/Escape operate it.
4. With no media or failed USB mount the MCU console hands video
   back after approximately 15 seconds. The Apple II reset already
   gets released by its independent watchdog.
5. If the storage message again says **0 BLK X 0 B**, test a known
   working USB 2.0 flash stick with FAT32 MBR and `DISK1.DSK`
   at the root, or choose the SD backend. The mass storage class
   SCSI initialization must report valid nonzero sector geometry.
6. Once disk boot works, run Mockingboard Demo Disk 1 and
   verify `P10 SPEECH BLOCKS` increments, `SEQGAP` stays zero,
   `SLOW` is low and FIFO occupancy remains stable.
