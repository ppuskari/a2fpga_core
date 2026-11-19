# SenseiPlay8 P2V — original NinjaTrackerPlus NTP v0 waveform-import experiment

**Status:** source and portable GitHub regressions pass; **hardware playback
is not yet verified**. P2U remains unchanged. This is an **MCU Stage 2-only**
revision; no FPGA HDL edits and no new ProDOS SYS.

- P2V branch: \`petar/sensei8-p2v-ntp-sample-bypass-20261119\`
- Parent: \`petar/sensei8-p2u-right-channel-audit-20261119\`
- Existing known-good FPGA: P2S/P2U Native DOC.
- Authoritative historical NTP format: Jesse Blue/NinjaForce
  \`ntpsources/file_format.txt\`, \`ntpconverter_lib.php\`,
  \`ninjatrackerplus.s\`.
- Source archive on GitHub:
  https://github.com/antoinevignau/source/tree/master/ntpsources
- Official documentation:
  https://www.ninjaforce.com/html/products_ninjatrackerplus.php

## Purpose / architectural distinction

The P2U MOD path decodes signed Amiga PCM on BL616, repacks attack/loop
samples and adds stop markers using our own algorithm. P2V adds a separate
\`.NTP\` option to the **existing HDMI/FAT32 SD/USB menu**. NTP
instrument samples have already been modified and placed for the IIgs
DOC by the ORIGINAL NinjaTrackerPlus converter. P2V copies those
**byte-for-byte**, preserving NTP stop markers, loop repetitions, DOC RAM
page pointers and actual DOC RTS register values. No XOR 0x80 or
0x00->0x01 or resampling is applied by a2fpga to an NTP waveform.

NTP pattern records (note index, instrument, effect, argument) are
translated in memory to the *existing* P2U four-channel ProTracker
tick-engine encoding. Crucially: this is **not yet a port of the original
NTP 65816 effects/replayer**. That is the next possible fidelity phase,
depending on results. A direct comparison of \`15k.mod\` and
original-converter \`15k.ntp\` isolates the **sample-preparation** variable
without touching the known-good FPGA audio hardware.

P2V accepts the documented \`nfc!\` **version 0** classic file layout:
four tracks, <=31 logical instruments (<=63 NTP records), up to 64KiB input file,
<=64KiB DOC Sound RAM image, no NTP streaming or name extensions.
NTP samples with extra 8 zero bytes preserve those bytes exactly.
The importer maps NTP sample types 0/1/2/3 and optimal-size bit 2
to DOC one-shot/free/swap oscillator settings. It rejects unsupported
effect opcodes rather than silently playing them wrong; the original
15k.mod effect inventory fits the existing subset.

NTP's per-track routing (0/2/4/6=left and 1/3/5/7=right) is preserved
from the NTP file. **It may be reversed relative to our P2U MOD default**.
The HDMI audition selector is therefore now CH0/CH1/CH2/CH3 and
PAIR 1+2 / PAIR 0+3, independent of which physical speaker is selected.

### Known limitations to test honestly

- For NTP type 2 attack followed by nonideal type 3 sustain, the
  original NTP 65816 player reacts to DOC waveform-end interrupts by
  changing the first oscillator's pointer to the sustain sample.
  P2V does **not yet reproduce that IRQ-driven retargeting**. It
  alternates the two oscillators via swap, so when the sustain ends
  the original attack can be replayed before returning to sustain.
  This is particularly relevant to short non-power-of-two loops
  (such as 15k instrument 5).
- P2U ProTracker effects still run, not original NinjaTrackerPlus
  assembly. Nonzero NTP finetune is not yet supported, so those files are
  rejected before any DOC upload; choose zero-finetune songs for this
  pass (all populated instruments in 15k.mod are finetune=0).
- NTP versions 1 and 2, streaming data, >4 channels, later appended
  metadata, and any unimplemented P2U effect are intentionally rejected.
  Use the archived original version-0 converter for testing; the
  current Ninjaforce web converter may generate newer file versions.
- The offline converter sources are not copied into a2fpga, avoiding
  licensing ambiguity. Build conversion assets locally from that
  original GitHub archive. Our independent format reader has tests.

## PowerShell 5.1: build host firmware (each line separately)

### 1. New isolated working copy

\`\`\`powershell
$hw = 'C:\AppleIIgsDev_02\a2fpga-sensei-p2v'
if (-not (Test-Path "$hw\.git")) { git clone --branch petar/sensei8-p2v-ntp-sample-bypass-20261119 --single-branch https://github.com/ppuskari/a2fpga_core.git $hw }
git -C $hw fetch origin petar/sensei8-p2v-ntp-sample-bypass-20261119
git -C $hw switch petar/sensei8-p2v-ntp-sample-bypass-20261119
git -C $hw pull --ff-only origin petar/sensei8-p2v-ntp-sample-bypass-20261119
git -C $hw log -1 --oneline
\`\`\`

### 2. Build MCU Stage 2

\`\`\`powershell
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
Get-Item "$env:BL_SDK_BASE\project.build"
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2v\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
make -j4 CHIP=bl616 BOARD=bl616dk
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
Get-FileHash .\build\build_out\a2n20_bl616_host_bl616.bin -Algorithm SHA256
\`\`\`

### 3. Flash Stage 2 *only*

\`\`\`powershell
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2v\boards\a2n20v2-Enhanced\src\a2n20_bl616
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
\`\`\`

NEVER run \`make flash\` and do not touch the signed Stage 1 at 0x0.
Stage 2 lives at 0x40000. Preserve the existing P2S FPGA bitstream.
If an MCU update power cycle resets volatile FPGA configuration:

\`\`\`powershell
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2s\boards\a2n20v2-Enhanced
openFPGALoader -b tangnano20k .\impl\pnr\a2n20v2_enhanced.fs
\`\`\`

No new SynthLab/SSI ROM extract and no Gowin rebuild required because
the FPGA source is identical to P2U.

## Produce a REAL \`15k.ntp\` using Jesse Blue's converter

The historical original NTP converter is a **PHP command-line program**.
Do not use our MOD decoder or a custom conversion script for this test.
No NTP converter source is redistributed in the P2V branch.

\`\`\`powershell
$converter = 'C:\AppleIIgsDev_02\ninjatrackerplus-original'
if (-not (Test-Path "$converter\.git")) { git clone --depth 1 https://github.com/antoinevignau/source.git $converter }
Get-Command php -ErrorAction SilentlyContinue
\`\`\`

If php is unavailable, Chocolatey may provide a package:

\`\`\`powershell
choco install php -y
\`\`\`

Open a fresh PowerShell window if Chocolatey changed PATH.

\`\`\`powershell
php -v
\`\`\`

Set this variable to the actual local location of **your original MOD**
(change the path rather than using a guessed SD drive letter):

\`\`\`powershell
$mod = 'C:\AppleIIgsDev_02\MODS\15k.mod'
Test-Path $mod
php "$converter\ntpsources\ntpconverter.php" $mod
Get-Item ([System.IO.Path]::ChangeExtension($mod,'.ntp')) | Select-Object FullName,Length,LastWriteTime
\`\`\`

The converter writes \`15k.ntp\` alongside \`15k.mod\` and reports
"UNABLE TO CONVERT" on a rejected/unsupported input. Copy the generated
file into the FAT32 SD card's \`MODS\` folder alongside the original MOD.

The newer official online converter can be used for other testing,
but P2V's v0-only importer will reject its modern NTP format until the
corresponding v1/v2 reader and stream metadata are added.

## Hardware comparison

1. Keep the original P2S FPGA/Native DOC personality and FAT32 SD/USB.
2. From HDMI USB keyboard TAB -> MOD LIBRARY, set AUDITION CHANNEL=ALL 4.
3. Play \`MODS/15k.mod\`; record HDMI audio and P2V log counters.
4. STOP and play \`MODS/15k.ntp\`; record same signal chain.
5. Compare against PT2 clone with A500/legacy channels, with *no*
   automatic crossfeed. Note NTP can encode opposite left/right pan:
   compare matching musical channel/instrument, not only speaker order.
6. Repeat CH2 ONLY and CH1 ONLY auditions as needed to isolate right-side
   sustain/one-shot behavior. NTP's stored pan determines actual speaker.
7. At STOP/done capture FPGA OVR/HIGH/LATE, MCU SENT/HIGH/LATE and
   NOTES CH0..CH3. Target FPGA OVR=0 and no MCU dropped event.
8. Log whether \`NTP NONIDEAL LOOPS\` appears. If timbral roughness
   persists on these loops, the **next engineering change is an exact
   NTP nonideal-loop IRQ/rearm implementation**, not sample conversion.

Expected console markers:

\`\`\`
SENSEI P2V: NTP V0 DOC PCM DIRECT
SENSEI P2V: PLAY MASK=0F
P2V NTP NONIDEAL LOOPS=...
\`\`\`

Please capture the exact line in case the importer rejects
the NTP file. Incorrect v1/v2 conversion should fail cleanly,
not corrupt DOC memory.

## Why this does NOT yet prove NTP player equivalence

P2V imports authentic NTP v0 sample data, pointers and pattern records
but still uses the existing P2U C effect engine. It is an experiment
that isolates the NTP converter's waveform preparation from P2U's.
Only a second pass using original NinjaTrackerPlus loop IRQ semantics
and its own effects/timing can establish full NTP playback parity.
