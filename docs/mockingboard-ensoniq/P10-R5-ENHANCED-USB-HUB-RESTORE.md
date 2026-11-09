# P10-R5 — Restore the exact November 6 Enhanced USB host configuration

**Board scope:** `boards/a2n20v2-Enhanced` only.

**Symptom:** USB keyboard/TAB still not responding after P10-R4,
despite restoring the native `usbh_hidinput.c` driver and menu code.

## Confirmed regression from source comparison

P10-R4 accidentally sourced its `usb_config.h` from older
`ppuskari/a2fpga_core:main` instead of the November 6 working
Enhanced baseline:

| CherryUSB configuration | P10-R4 | November 6 baseline |
|---|---:|---:|
| `CONFIG_USBHOST_MAX_EHPORTS` | 4 | **8** |
| `CONFIG_USBHOST_REQUEST_BUFFER_LEN` | 512 | **1024** |

CherryUSB can fail to enumerate a hub when `bNbrPorts` exceeds
`MAX_EHPORTS`, preventing *all* devices behind the hub from
appearing. Composite devices may also fail when their configuration
descriptors exceed the EP0 request buffer.

**P10-R5 restores the exact November 6 `usb_config.h` file**
(blob SHA `ab73305fbf9164142cf51a0dd121565fc3bcf2fc`).
The original HID `usbh_hidinput.[ch]`, `proj.conf`, `menu.c`,
`osd_console.[ch]` are independently confirmed identical to the
November 6 Enhanced branch.

**This is a strong potential cause, not yet an on-device proof.**
A keyboard connected directly to the BL616 USB-host port rather
than via a hub is a useful additional isolation test.

No FPGA RTL, DOC piano, SSI register controller, PCM bridge or
Pico speech engine changed. No speech-task priority or numerical
precision changes were added to this branch: it isolates USB
enumeration compatibility.

## One-line PowerShell build

After saving your existing P10-R4 Stage2 binary elsewhere:

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10
```

```powershell
git status --short
```

```powershell
git fetch origin
```

```powershell
git switch --track origin/petar/ssi263-p10r5-enhanced-usb-hub-restore-20261109
```

```powershell
Set-Location .\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
```

```powershell
make -j4
```

```powershell
Select-String -Path .\usb_config.h -Pattern 'CONFIG_USBHOST_MAX_EHPORTS|CONFIG_USBHOST_REQUEST_BUFFER_LEN'
```

```powershell
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin
```

Only after Bouffalo SDK 2.3.27 finishes successfully and rollback
image is saved, from parent `a2n20_bl616` directory:

```powershell
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

Keep the existing timing-closed P10-R2 FPGA bitstream; **never flash
Stage 1 or address 0x00000**. The programmer's prior `--verify-flash`
reported read-back file not found, so a successful write message
alone does not prove byte-for-byte verification.

## Hardware acceptance

1. On the BL616 USB HOST port, connect the original keyboard/hub;
   look for `USB HOST: KEYBOARD CONNECTED`.
2. TAB switches Apple/MCU video; arrows and Enter operate menu.
3. Without USB disk image, MCU OSD returns to Apple video after
   the expected 15-second failure timeout.
4. Pico speech continues to report its `RATE / CPU / SPI / UND`
   measurements. Do not mix in new audio tuning until HID works.
5. If keyboard still fails, compare direct-port vs hub and
   collect USB enumeration logs. Separately test suppressing the
   speech FreeRTOS task to isolate scheduler interference.

CI guard: `.github/workflows/ssi263-p10r5-enhanced-usb-hub-restore.yml`.
