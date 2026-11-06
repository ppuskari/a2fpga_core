# BL616 Enhanced firmware: Windows 10/11, PowerShell 5.1, VS Code, and safe two-stage flashing

This is a **Windows-native** setup and deployment guide for the Tang Nano 20K / A2N20V2-Enhanced BL616 MCU. No WSL, Linux, or macOS is required. All PowerShell commands below occupy **one physical line** and work in PowerShell 5.1.

**Important keyboard regression fix (6 November 2026):** The earlier `petar/mcu-screen-idle-timeout-15s` development branch was based on an older firmware snapshot that **lacked USB HID keyboard support** (`usbh_hidinput.c`, the HID SDK setting, and keyboard polling in `main.c`). Consequently the newly flashed MCU timeout worked, but USB keyboard **Tab no longer opened the menu**. This replacement branch is based directly on current official `a2fpga/a2fpga_core` `main` (commit `5a35b0edb0e6593b030f007da6e3156e89d133b5`) and adds only the same three MCU timeout changes. The official HID keyboard implementation is retained. **Use this new branch for the MCU build; the old branch is superseded.** This combined branch requires compilation and hardware verification; its keyboard restoration has not yet been hardware-tested.

**Hardware validation (6 November 2026):** Stage 1 and Stage 2 were programmed and verified by flash readback on an **AES-128 fused BL616**, using Windows COM13. The Enhanced FPGA/MCU subsequently operated on an **Apple IIe**, with virtual Mockingboard in slot 4 and native YM2149 audio over HDMI. The separate **15-second MCU console/menu idle-timeout** change on `petar/mcu-timeout-hid-upstream-20261106` was then compiled, deployed, and reported **working on hardware**. This is a field result for that setup, not a guarantee for other boards or toolchain versions.

> **Critical safety:** The BL616 has two flash stages. The *correct* **Stage 1 bootloader** goes at `0x00000`; the **Enhanced USB-host application** goes at `0x40000`. On fused chips, a generic, unsigned program at `0x00000` prevents normal boot. **Never use `make flash`, a raw `BLFlashCommand` at `0x0`, or an arbitrary Stage 1 image.** Only the repo's `tools/a2n20-mcu-program` should be used for Stage 1 recovery: it checks the BL616 eFuse state and selects the compatible factory/recovery image. Ordinary MCU updates should flash **Stage 2 only**.

## 1. Know the three firmware images

| Binary | Directory | Observed size (reference revision) | Use |
| --- | --- | ---: | --- |
| `a2n20_bl616_bl616.bin` | `firmware/build/build_out/` | 93,296 bytes | USB *device* firmware: FT2232/JTAG/serial bridge; **not** the Enhanced USB-host application |
| `a2n20_bl616_host_bl616.bin` | `firmware_host/build/build_out/` | 308,736 bytes in upstream baseline; earlier revisions 298,448 | Enhanced **USB-host** runtime (disk serving, dynamic slots, keyboard/gamepad, menu) |
| `bl616_fpga_partner_20kNano.bin` / `friend_20k_bl616.bin` | `recovery/` | 90,672 / 89,024 bytes in tested repo | Alternative **Stage 1** recovery images; only one is compatible with a particular BL616 eFuse state |

The host binary size will change when you recompile it. **Do not demand that your newly built binary remain 308,736 bytes.** Inspect its timestamp, SHA-256 and build outcome instead.

The FPGA `.fs` image (compiled in Gowin) and the BL616 `.bin` firmware are **separate installations**. Programming one does not program the other.

## 2. Windows prerequisites

- Windows 10/11 with PowerShell 5.1, Git, Python 3 (`py -3`), VS Code (optional but convenient), and 7-Zip.
- A suitable USB-C **data** cable for the Tang Nano 20K **Debug** port, access to the recessed **UPDATE** button near HDMI, and the correct Enhanced FPGA `.fs` installed.
- Python package `bflb-iot-tool` (brings in `pyserial`) for BL616 programming.
- **BouffaloSDK tag `v2.3.27`**, which supplies **CherryUSB v1.5.3**.
- **Xuantie/T-Head Windows RISC-V GCC** from Bouffalo's **`compact-old`** toolchain release. A generic upstream RISC-V compiler can lack the E907 ISA extensions. The current GCC 14.x vendor toolchain is not the conservative choice for this pinned SDK.

Useful vendor links:

- [Pinned BouffaloSDK](https://github.com/bouffalolab/bouffalo_sdk/tree/v2.3.27)
- [Compatible legacy Xuantie release](https://github.com/bouffalolab/toolchain/releases/tag/compact-old)
- [Windows x64 archive: `xuantie-gcc-riscv-v2.10.2-windows-x86_64.7z`](https://github.com/bouffalolab/toolchain/releases/download/compact-old/xuantie-gcc-riscv-v2.10.2-windows-x86_64.7z)
- [Official A2N20 MCU programmer](../tools/a2n20-mcu-program)

Check Python and Git:

```powershell
py -3 --version; git --version
```

Install the flash dependencies:

```powershell
py -3 -m pip install --user --upgrade bflb-iot-tool pyserial
```

If `bflb-iot-tool` is missing from PATH, add Python's user Scripts folder to the current shell:

```powershell
$env:Path=((& py -3 -c "import sysconfig;print(sysconfig.get_path('scripts',scheme='nt_user'))").Trim())+';'+$env:Path; Get-Command bflb-iot-tool -ErrorAction Stop
```

## 3. Clone the project and *pinned* SDK

These paths are examples consistent with the successful Windows setup. Adjust `C:\AppleIIgsDev_02` if your workspace differs.

Checkout the corrected **upstream HID + 15-second timeout** branch without modifying your stock/golden FPGA working copy:

```powershell
git clone --branch petar/mcu-timeout-hid-upstream-20261106 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mcu-timeout-hid
```

Checkout the SDK using the **tag**, not the moving `master` branch:

```powershell
git clone --branch v2.3.27 --depth 1 https://github.com/bouffalolab/bouffalo_sdk.git C:\AppleIIgsDev_02\bouffalo_sdk
```

Verify that the SDK and CherryUSB are the intended revisions:

```powershell
git -C C:\AppleIIgsDev_02\bouffalo_sdk describe --tags; Select-String -Path C:\AppleIIgsDev_02\bouffalo_sdk\components\usb\cherryusb\common\usb_version.h -Pattern CHERRYUSB_VERSION_STR
```

Expected: `v2.3.27` and `#define CHERRYUSB_VERSION_STR "v1.5.3"`. If either differs, correct the checkout before building.

## 4. Install the Windows Xuantie cross-compiler

Create a tools directory:

```powershell
$tools='C:\AppleIIgsDev_02\bouffalo_tools'; New-Item -ItemType Directory -Force -Path $tools | Out-Null
```

Download the legacy Windows x64 vendor compiler (the archive size below was verified against the 2026 Bouffalo release):

```powershell
$archive=Join-Path $tools 'xuantie-gcc-riscv-v2.10.2-windows-x86_64.7z'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/bouffalolab/toolchain/releases/download/compact-old/xuantie-gcc-riscv-v2.10.2-windows-x86_64.7z' -OutFile $archive; if ((Get-Item $archive).Length -ne 38669673) { throw 'Unexpected compiler archive size' }
```

Install 7-Zip if needed (requires an elevated terminal when using Chocolatey):

```powershell
choco install 7zip.install -y
```

Extract the archive:

```powershell
$sevenzip=Join-Path $env:ProgramFiles '7-Zip\7z.exe'; if (!(Test-Path $sevenzip)) { throw '7-Zip not found' }; & $sevenzip x $archive "-o$tools\xuantie" -y; if ($LASTEXITCODE -ne 0) { throw 'Compiler extraction failed' }
```

**Configure the compiler and build tools for each new PowerShell session.** The SDK supplies Windows GNU Make and CMake, so you do not need Visual Studio's native C compiler. Find the cross-compiler executable instead of assuming the extraction's top-level folder name:

```powershell
$sdk='C:\AppleIIgsDev_02\bouffalo_sdk'; $gcc=Get-ChildItem "$tools\xuantie" -Filter 'riscv64-unknown-elf-gcc.exe' -Recurse -File | Select-Object -First 1; if (!$gcc) { throw 'T-Head GCC missing' }; $env:BL_SDK_BASE='C:/AppleIIgsDev_02/bouffalo_sdk'; $env:Path=$gcc.Directory.FullName+';'+(Join-Path $sdk 'tools\make')+';'+(Join-Path $sdk 'tools\cmake\bin')+';'+(Join-Path $sdk 'tools\ninja')+';'+$env:Path; Write-Host "Compiler: $($gcc.FullName)"
```

Check the installed executables:

```powershell
riscv64-unknown-elf-gcc --version; make --version; cmake --version
```

Make sure `Get-Command riscv64-unknown-elf-gcc` points to **Xuantie** and not a second RISC-V compiler. The `firmware_host/Makefile` chooses `riscv64-unknown-elf-` as the cross-compiler prefix.

## 5. Compile the Enhanced *host* firmware from PowerShell or VS Code

The **host** application lives in `boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host`, not the similarly named `firmware` directory.

Set the firmware directory:

```powershell
$root='C:\AppleIIgsDev_02\a2fpga-mcu-timeout-hid\boards\a2n20v2-Enhanced\src\a2n20_bl616'; Set-Location "$root\firmware_host"
```

Build with GNU Make:

```powershell
make CHIP=bl616 BOARD=bl616dk
```

The project pins `SDK_DEMO_PATH` to an absolute directory through its Makefile, and the vendor make system invokes CMake. A successful build reports **`Built target combine`** and writes:

```text
firmware_host\build\build_out\a2n20_bl616_host_bl616.bin
```

Check that the output exists, and record its size, timestamp, and hash:

```powershell
$f=Join-Path $root 'firmware_host\build\build_out\a2n20_bl616_host_bl616.bin'; if (!(Test-Path $f)) { throw 'Host firmware build output missing' }; Get-Item $f | Select-Object FullName,Length,LastWriteTime; Get-FileHash $f -Algorithm SHA256
```

If CMake cached a **different SDK or compiler**, remove the generated `firmware_host\build` directory **only after confirming it contains no files you need**, then run Make again:

```powershell
Set-Location "$root\firmware_host"; if (Test-Path .\build) { Remove-Item .\build -Recurse -Force }; make CHIP=bl616 BOARD=bl616dk
```

### VS Code workflow

1. Open the host firmware folder in VS Code:

   ```powershell
   code C:\AppleIIgsDev_02\a2fpga-mcu-timeout-hid\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
   ```

2. Select **Terminal → New Terminal**, choose **PowerShell**, and repeat the environment-variable setup from section 4 in that terminal. VS Code does not automatically inherit variables you set in an unrelated PowerShell window.
3. Run `make CHIP=bl616 BOARD=bl616dk` from the firmware_host directory. Edit `menu.c`, `osd_console.c` and `osd_console.h` normally in VS Code.
4. The C/C++ extension is optional for navigation and IntelliSense. It is **not** the cross-compiler. The external vendor GCC toolchain remains responsible for producing the binary.

For the corrected timeout branch, these are the three intended source changes (the upstream USB HID driver remains present):
- `menu.c`: return from the menu after 15 seconds without controller/USB-keyboard/remote input.
- `osd_console.c` and `osd_console.h`: hide the otherwise persistent boot console 15 seconds after the last visible diagnostic activity.
- Firmware/FPGA installation screens retain their existing installation lockout; the timeout does **not** replace or alter the DOC/FPGA RTL.

## 6. Enter BL616 ROM boot mode from Windows

1. Power the Apple II off and disconnect Debug USB-C from the PC.
2. **Hold UPDATE** (recessed button near HDMI).
3. While holding UPDATE, connect a **data-capable** USB-C cable to the Tang Nano 20K **Debug** connector and Windows PC.
4. Release UPDATE. The board should enumerate as a Bouffalo CDC serial port (e.g. `COM13` in the field test).
5. Never use a live USB-host/gamepad port as a substitute for the Debug/ROM boot connection.

Enumerate serial ports:

```powershell
py -3 -m serial.tools.list_ports -v
```

Use the repo's programmer in **detect-only mode** before writing:

```powershell
py -3 "$root\tools\a2n20-mcu-program" --detect
```

The hardware field test reported:

```text
[DETECTED] Bouffalo BootROM (boot/recovery mode)
COM13
eFuse state: FUSED (sign=0, encrypt=1: AES-128)
Correct Stage 1: bl616_fpga_partner_20kNano.bin
```

This classification is **specific to that board**. Other boards may be unfused. The programmer reads the BootROM's eFuse information and selects either the encrypted Sipeed image (`bl616_fpga_partner_20kNano.bin`) or plaintext `friend_20k_bl616.bin`. **If eFuse identification fails, stop rather than forcing a guessed Stage 1.**

## 7. First installation or old chain-loader: Stage 1 **and** Stage 2

For first-time Enhanced initialization, or when a verified Stage 2 cannot launch because the existing factory Stage 1 lacks `0x40000` chain-load support, use the repository's safe combined command. It automatically chooses a compatible Stage 1 after eFuse probing.

Confirm the local recovery binaries and the host application exist:

```powershell
$files=@(@('recovery\bl616_fpga_partner_20kNano.bin',90672),@('recovery\friend_20k_bl616.bin',89024)); foreach($x in $files){$p=Join-Path $root $x[0]; if(!(Test-Path $p) -or (Get-Item $p).Length -ne $x[1]) { throw "Missing or unexpected recovery file: $p" }}; $host=Join-Path $root 'firmware_host\build\build_out\a2n20_bl616_host_bl616.bin'; if(!(Test-Path $host)){throw 'Missing host firmware'}
```

**Only while the BL616 is already in ROM boot mode**, execute:

```powershell
py -3 "$root\tools\a2n20-mcu-program" --stage1 --stage2 --firmware "$root\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin" --non-interactive --verify-flash
```

Expected evidence from the successful Windows hardware installation:

```text
Mode: Manual — flash firmware at 0x0 + firmware at 0x40000
eFuse state: FUSED (sign=0, encrypt=1: AES-128)
Selected: bl616_fpga_partner_20kNano.bin
[OK] Stage 1 flashed successfully (baud 500000)
[OK] verified 90672 bytes at 0x0 match the image
[OK] Stage 2 flashed successfully (baud 500000)
[OK] verified 308736 bytes at 0x40000 match the image
Programming complete!
```

The Stage 2 byte count above is the original 308,736-byte image; a rebuilt version reports **its own** size. **`--non-interactive` skips the utility's post-reboot runtime check, but `--verify-flash` still attempts byte-for-byte flash readback.** Require explicit `[OK] verified ... match` messages for both stages. A warning that readback was skipped is not proof of verification.

If you already have a functioning Stage 1, **do not repeat this combined process for routine updates**.

## 8. Routine updates: reflash **Stage 2 only**

After compiling a firmware modification, repeat the UPDATE-button ROM boot sequence. Then use:

```powershell
py -3 "$root\tools\a2n20-mcu-program" --stage2 --firmware "$root\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin" --non-interactive --verify-flash
```

This targets **`0x40000` only**; it preserves the known-good signed Stage 1. Verify the Stage 2 readback and then disconnect Debug USB-C before normal Apple II operation.

**Do not invoke `make flash`.** The firmware Makefile deliberately disables it as a safety guard.

## 9. Boot, verify, and test the 15-second timeout

1. Flash the Enhanced FPGA bitstream separately (Gowin) if it is not already installed. For native Mockingboard validation, keep the **stock Enhanced FPGA** as the control image.
2. Disconnect the Windows PC **Debug USB-C** cable. On the fused board, Stage 1 only chain-loads Stage 2 for normal standalone operation when no PC/JTAG host is present.
3. Attach a wired USB keyboard or supported gamepad through the BL616 USB-host/OTG connector (connect before power-up when using a hub).
4. Boot the **Apple IIe**. The MCU's initial console may show while storage and slots initialize. The virtual slot map is normally `0 0 3 5 2 4 6 1`; card ID `2` is Mockingboard in slot `4`.
5. With the updated MCU firmware, the boot console returns to Apple video after about **15 seconds without new visible diagnostic messages**, even when a USB storage mount fails. You can still view the diagnostics later.
6. **Tab** on the USB keyboard (or **SELECT** on a recognized gamepad) toggles Apple video ↔ MCU. **Y** switches MCU menu ↔ console. Arrow keys navigate, **Enter** selects, **Esc/Backspace** goes back. The Apple II keyboard is *not* the MCU menu keyboard.
7. Configure **SLOT ASSIGNMENTS** to only Mockingboard in slot 4 for a controlled experiment; apply and reboot. A stock Enhanced board with this configuration was hardware-tested successfully with the Mockingboard demonstration floppy: native AY/YM sound through HDMI.
8. Open the MCU menu and stop interacting. It should return to Apple video after **15 seconds idle**. Active input resets the timer; firmware/FPGA installation remains exempt.
9. Only after the native baseline passes, flash the experimental Mockingboard-to-DOC FPGA image and compare the VIA, AY capture, DOC oscillator and HDMI paths.

### Troubleshooting quick reference

| Symptom | Check |
| --- | --- |
| Stage 2 flashes and verifies, but no MCU startup/menu | Stage 1 may be too old to chain-load `0x40000`. Use the eFuse-aware **Stage 1 + Stage 2** procedure **only when indicated**. |
| MCU console stays visible and keyboard/gamepad doesn't switch | USB host device may not have enumerated. Try a wired USB keyboard, direct OTG/data adapter, and connecting before power-on. |
| `USB MOUNT FAILED (FR=1)` or `USB 0 BLK x 0 B` | USB storage or block-read path failure, not a missing `disk1.dsk` alone. Use a FAT32/MBR stick and inspect console logs. |
| No native Mockingboard | Verify the menu's **live** slot 4 is Mockingboard; the MCU can override `slots.hex` at boot. Retest with stock Enhanced FPGA and a real demonstration disk. |
| Build cannot find `riscv64-unknown-elf-gcc` | Re-run the toolchain PATH step in the *same* PowerShell/VS Code terminal as Make. |
| Build errors from CherryUSB APIs | Confirm SDK `v2.3.27`, CherryUSB `v1.5.3`, and the legacy Xuantie compiler. Don't silently switch to SDK master or current GCC. |
| Build links to old SDK/toolchain | Clear generated `firmware_host/build` and rebuild; keep `BL_SDK_BASE` explicitly set. |
| Python sees no Bouffalo COM port | Re-enter ROM boot mode by holding UPDATE **while connecting** the Debug cable; verify USB data cable and Windows device enumeration. |

## Reference sources and reproducibility

- [Enhanced board installation guide](../../../README.md)
- [MCU architecture, eFuse and recovery details](../README.md)
- [Vendor SDK v2.3.27](https://github.com/bouffalolab/bouffalo_sdk/tree/v2.3.27)
- [Vendor legacy compiler release](https://github.com/bouffalolab/toolchain/releases/tag/compact-old)

This guide preserves the exact **PowerShell 5.1 + VS Code** workflow used during the successful Apple IIe deployment. The original timeout was hardware-proven by the project owner, **but the upstream-HID-combined replacement branch has not yet been hardware-tested**. Verify Tab, arrows, Enter, Y, timeout, and return to Apple video after flashing the rebuilt Stage 2.
