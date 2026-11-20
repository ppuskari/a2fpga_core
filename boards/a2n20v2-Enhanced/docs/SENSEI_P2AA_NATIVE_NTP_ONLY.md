# SenseiPlay8 P2AA — native NTP-only MCU, clean legacy removal

**Status: MCU-only experimental recovery candidate.** No FPGA HDL change,
no piano/SSI263 asset change. Not yet proven on physical Apple IIe.
Portable regression CI does not prove hardware stability.

Repository: `ppuskari/a2fpga_core`
Branch: `petar/sensei8-p2aa-native-ntp-only-20261120`
Parent: `petar/sensei8-p2z-ntp-stack-safety-20261120`

## Scope

The P2Y/P2Z hardware report was **no sound, menu freeze after NTP
selection**. Root cause is not established. P2Z moved stack-heavy
structures to static BSS and increased the worker stack to 4 KB.

P2AA deletes the obsolete `sensei_mod_player.c/.h` and
`sensei_mod_decode.c/.h` and their legacy MOD/prototype tests in this
new branch. It also removes the P2V/P2W NTP-to-ProTracker shadow
pattern conversion and its second pattern allocation. Native .NTP files
now allocate precisely one immutable file buffer and one DOC PCM bank,
then play their raw pattern bytes directly through the independent C
NinjaTrackerPlus interpreter. The legacy P1D/P1E synthetic tracker
entry points are removed.

**Retained:** `sensei_ntp_native.c`, strict v0/v2 raw NTP instrument
parser, byte-exact DOC PCM, FAT32 disk broker, SPI6 FIFO, DOC Sound RAM
DMA, P2Y waveform-end FPGA assist, original August DOC SWAP core,
A3 persistent audio selection, SSI263, SynthLab ROMs, and original
ProDOS `SENSEI8.SYSTEM` client.

The generic disk broker opcode names `FSOP_MOD_OPEN/READ/CLOSE`
remain unchanged for compatibility; the loader now accepts **only
`.ntp` files**. The MCU menu displays **NTP LIBRARY**.
This is a deliberate loss of `.mod` playback on this branch.
The historical MOD-capable firmware is recoverable from older branches.

## Windows PowerShell 5.1 — paste one command per line

### 1. Source

```powershell
$hw = 'C:\AppleIIgsDev_02\a2fpga-sensei-p2aa'
if (-not (Test-Path "$hw\.git")) { git clone --branch petar/sensei8-p2aa-native-ntp-only-20261120 --single-branch https://github.com/ppuskari/a2fpga_core.git $hw }
git -C $hw fetch origin petar/sensei8-p2aa-native-ntp-only-20261120
git -C $hw switch petar/sensei8-p2aa-native-ntp-only-20261120
git -C $hw pull --ff-only origin petar/sensei8-p2aa-native-ntp-only-20261120
git -C $hw log -1 --oneline
```

### 2. FPGA Gowin GUI — NOT REQUIRED

All FPGA sources are unchanged from P2Y/P2Z. No synthesis, placement,
timing, or bitstream generation is required for P2AA.
If a power cycle cleared the previous P2Y FPGA test bitstream from
volatile SRAM, use Gowin GUI to reload that same known P2Y image
into SRAM. Do not program persistent FPGA flash before audio validation.
Use the original working `a2n20v2-Enhanced` Gowin project.

### 3. Audio assets — NOT REQUIRED

No piano/voice .mem extraction or asset generation in P2AA.
Do not rebuild them unless you choose to rebuild FPGA separately.

### 4. MCU BL616 Stage 2 cross-build

```powershell
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
Get-Item "$env:BL_SDK_BASE\project.build"
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host"
make -j4 CHIP=bl616 BOARD=bl616dk
if ($LASTEXITCODE -ne 0) { throw 'P2AA MCU build failed; do not flash' }
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
Get-FileHash .\build\build_out\a2n20_bl616_host_bl616.bin -Algorithm SHA256
```

### 5. Program BL616 Stage 2 only, signed Stage 1 untouched

```powershell
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616"
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

**Never** `make flash` or overwrite signed BL616 Stage 1 at 0x00000;
the application is Stage 2 at 0x40000.

## Hardware test

- Start from **Native DOC** audio mode and P2Y/P2Z FPGA in SRAM.
- Verify menu now reads **NTP LIBRARY** and lists .NTP files only.
- Select `15k.ntp`; log last message if screen/menu freezes.
- Expected log progression:

```text
SENSEI P2AA: NTP-ONLY 4K WORKER
P2AA: LOADING NTP FILE
P2AA: PCM ... BYTES; BEGIN DMA
P2AA: DOC PCM DMA VERIFIED
SENSEI P2AA: NTP V2 NATIVE ONLY
SENSEI P2AA: MASK=0F NONIDEAL=...
```

- Test STOP (menu responsiveness) before checking stereo and effects.
- Repeatedly open/stop/reopen a song; observe heap exhaustion and
  PCM upload errors.
- Capture MCU console, FPGA FIFO OVR/HIGH/LATE, and NOTES CH0–CH3.

If freeze happens before `PCM ... BYTES`, inspect FAT broker and
parse/allocation. If before `DOC PCM DMA VERIFIED`, inspect
SPI6 DMA and SDRAM ACK flow. If after `NTP V2 NATIVE ONLY`,
inspect tracker scheduler, waveform retarget, and DOC ownership.

Full BL616 build, physical audio and menu stability are not verified by
the portable CI. Do not call P2AA production-ready based only on CI.
