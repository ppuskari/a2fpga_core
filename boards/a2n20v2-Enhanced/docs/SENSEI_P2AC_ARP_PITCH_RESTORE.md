# SenseiPlay8 P2AC: restore stable sample playback during arpeggios

**Status: MCU-only experimental hardware fix.** Not yet verified on physical
Apple IIe. Parent is P2AB, which caused high-pitched/fast-sounding samples
and still had missing melody notes on hardware. Previous P2AA had stable
menu and correct L/R output but poor sustains.

Branch `petar/sensei8-p2ac-arpeggio-pitch-fifo-20261120`

## Root-cause narrowing

P2AB changed every nonzero `0xy` arpeggio effect tick from a four-event
DOC frequency update into a complete A/B sample restart. This can
repeatedly replay the attack, interrupt B sustain, and increase bursts
into the 64-event FPGA FIFO. It needlessly reprograms WTP/RTS/VOL/CTRL
when only frequency needs to change.

P2AC:
- Restores **four FC writes only** (low/high for both oscillators) on
  `0xy` effect ticks. Does not reset DOC attack/sustain mid-note.
- Uses integer note indices into the existing reference-frequency table,
  replacing approximate semitone multipliers.
- Retains P2AB's tick-zero recovery of a note-less `0xy` row, which
  is documented in original NinjaTrackerPlus and occurs in 15k.ntp.
- Keeps original DOC SWAP FPGA HDL and sound assets **byte-for-byte**.
- Outputs OSD `SENSEI P2AC: NTP V2 PITCH ONLY`.
- Adds regression assertions: one tick-zero root restart, then precisely
  four pitch-only writes and zero A/B CTRL or waveform-pointer writes
  on each effect tick.

Note the actual 15k.ntp has its first nonzero `0xy` at order 3 row 56.
P2AB's arpeggio change cannot alter the opening music before that.
If opening notes **also** sound two octaves high, another issue exists:
check FPGA image, audio mode and hardware state before concluding this
arpeggio fix addresses the global pitch complaint.

## 64-event FIFO observation

The FPGA `sensei_tracker_bridge.sv` has `FIFO_AW=6`, exactly 64 entries.
A reported high-water of 64 means its backlog **reached capacity**.
OVR=0, LATE=0 does not prove the DOC sample itself is correct; it does
indicate no observed FIFO event overflow or late execution. P2AC
reduces arpeggio write traffic but may not eliminate initial peak=64,
because tracker initialization and four simultaneous note starts can
already fill most of the FIFO. The persistent sustain fault remains
open, and needs real DOC memory-fetch timeout/late-response diagnostics.

The 15k A/B P2AA WAV's opening 65, 87 and 174 Hz dominant pitches were
nearly identical to the PT2 reference. This supports **stable original
note frequency** at the beginning of the song; it does not prove the
latest P2AB hardware playback has correct pitch.

## PowerShell 5.1 (individual single-line commands)

### 1. Isolated source checkout

```powershell
$hw = 'C:\AppleIIgsDev_02\a2fpga-sensei-p2ac'
if (-not (Test-Path "$hw\.git")) { git clone --branch petar/sensei8-p2ac-arpeggio-pitch-fifo-20261120 --single-branch https://github.com/ppuskari/a2fpga_core.git $hw }
git -C $hw fetch origin petar/sensei8-p2ac-arpeggio-pitch-fifo-20261120
git -C $hw switch petar/sensei8-p2ac-arpeggio-pitch-fifo-20261120
git -C $hw pull --ff-only origin petar/sensei8-p2ac-arpeggio-pitch-fifo-20261120
git -C $hw log -1 --oneline
```

### 2. Gowin GUI FPGA: no compile or reflash

The P2Y FPGA bitstream and all PCM SynthLab/SSI263 assets are unchanged.
Keep the last tested P2Y FPGA in SRAM; reload using Gowin GUI to SRAM
only if power-cycled. Do not replace persistent FPGA flash.

### 3. Build MCU Stage 2

```powershell
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
Get-Item "$env:BL_SDK_BASE\project.build"
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host"
make -j4 CHIP=bl616 BOARD=bl616dk
if ($LASTEXITCODE -ne 0) { throw 'P2AC MCU build failed; do not program' }
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
Get-FileHash .\build\build_out\a2n20_bl616_host_bl616.bin -Algorithm SHA256
```

### 4. Stage 2 application programmer (signed Stage 1 is protected)

```powershell
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616"
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

Never use `make flash`, never write signed bootloader Stage1 at 0x0.
Stage2 application starts at flash 0x40000.

## Hardware acceptance

1. Set Native DOC, P2Y FPGA SRAM image, and browse `15k.ntp`.
2. Check OSD `SENSEI P2AC: NTP V2 PITCH ONLY`.
3. Compare **opening** melody/sample pitches with P2AA and PT2 first.
4. Compare later arpeggio passages after order 3 row 56; these should
   no longer sound like a rapidly restarted attack.
5. Observe FPGA `OVR/HIGH/LATE`, MCU `LATE/MAXMS`, and DOC SDRAM
   waveform-fetch timeout/late-response diagnostics under playback.
6. Test isolated right pair and left pair if notes still appear missing.
7. Revert to known-good P2AA if P2AC worsens any earlier passage.

Portable CI tests are not a substitute for BL616 cross-compile, Gowin
hardware synthesis, or physical audible verification.
