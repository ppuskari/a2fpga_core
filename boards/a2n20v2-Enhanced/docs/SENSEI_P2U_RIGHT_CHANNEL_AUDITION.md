# SenseiPlay8 P2U — right-channel audition and corrected MOD vibrato

Branch: \`petar/sensei8-p2u-right-channel-audit-20261119\`
Based on P2T. **Portable GitHub CI tested; no hardware playback verified yet.**
The physical P2S/P2T FPGA image is unchanged; **only BL616 MCU
Stage 2 needs rebuilding**. Golden and other music branches are untouched.

## Why

The 15k Boogie P2T physical recording has the intended stereo orientation
and no FPGA queue overflows, but has frequent low-energy/silent intervals
in the right channel compared with VLC. Existing event-count and FIFO
counters only prove delivery of DOC register writes, not emitted audio.

The supplied 15k.mod instrument/pattern audit found:
- ProTracker MOD CH1 (right): one note every pattern row, primarily
  instruments 6,7,8, which have **no sample sustain loops**. Their one-shot
  tails are naturally short and should not be misclassified as transport
  dropouts.
- MOD CH2 (right): instrument 5 contains a 6-byte attack and a 24-byte
  sustain loop. The tiny non-power-of-two sustain loop is repeated into
  a 256-byte DOC waveform and may cause fidelity discontinuities.
- CH2 carries most of the vibrato/combined volume effects.
  P2T incorrectly scaled ProTracker vibrato by /256 instead of /128,
  and advanced the phase by speed rather than 4*speed.

## What P2U does

1. Corrects ProTracker vibrato phase and depth in the **runtime C
   interpreter**. Retrigger, pitch, sample upload, stereo panning and the
   P2S queue are unchanged.
2. Adds an **AUDITION CHANNEL** choice to the existing HDMI MOD LIBRARY.
   Options: ALL 4 (default), CH0 LEFT, CH1 RIGHT, CH2 RIGHT, CH3 LEFT,
   RIGHT 1+2, LEFT 0+3.
3. The whole ProTracker pattern runs at its original timing regardless of
   which channel is audible. The audition mask only suppresses register
   writes to muted DOC oscillators; Bxx/Fxx/E6x playback flow remains
   active. Audition changes take effect **on the next song start**.
4. Adds per-channel note-start counters and short, full-width P2U FPGA
   and MCU queue diagnostics that fit the 39-column console.
5. Uses the existing FAT32 USB/SD picker. No IIe SYS required for menu
   playback; Native DOC must already be selected.

## PowerShell 5.1 (one command per paste)

### Checkout — preserve P2S/P2T

\`\`\`powershell
$hw = 'C:\AppleIIgsDev_02\a2fpga-sensei-p2u'
if (-not (Test-Path "$hw\.git")) { git clone --branch petar/sensei8-p2u-right-channel-audit-20261119 --single-branch https://github.com/ppuskari/a2fpga_core.git $hw }
git -C $hw fetch origin petar/sensei8-p2u-right-channel-audit-20261119
git -C $hw switch petar/sensei8-p2u-right-channel-audit-20261119
git -C $hw pull --ff-only origin petar/sensei8-p2u-right-channel-audit-20261119
git -C $hw log -1 --oneline
\`\`\`

### MCU build — required

\`\`\`powershell
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
Get-Item "$env:BL_SDK_BASE\project.build"
git -C $env:BL_SDK_BASE describe --tags
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2u\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
make -j4 CHIP=bl616 BOARD=bl616dk
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
Get-FileHash .\build\build_out\a2n20_bl616_host_bl616.bin -Algorithm SHA256
\`\`\`

### BL616 Stage 2 update — protect Stage 1

\`\`\`powershell
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2u\boards\a2n20v2-Enhanced\src\a2n20_bl616
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
\`\`\`

**Never \`make flash\` and never update BL616 Stage 1 at 0x0**.
Only Stage 2 at 0x40000 is programmed by the wrapper. If the update
power-cycled the FPGA, reload the known working P2S image into **SRAM**
(no \`-f\`):

\`\`\`powershell
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2s\boards\a2n20v2-Enhanced
openFPGALoader -b tangnano20k .\impl\pnr\a2n20v2_enhanced.fs
\`\`\`

### Optional — full FPGA rebuild if restoring from scratch

Not necessary for this P2U experiment. Source RTL is identical to P2S.
Only if a fresh FPGA binary is needed, in P2U checkout:

\`\`\`powershell
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2u
py -3 tools\extract_synthlab_piano.py --download
py -3 tools\extract_synthlab_piano.py --check
py -3 tools\generate_ssi263_voice.py
py -3 tools\generate_ssi263_voice.py --check
py -3 tools\generate_ssi263_p8_roms.py --check
py -3 tools\generate_ssi263_p9_nas_rom.py --check
py -3 tools\generate_ssi263_p9_output_fir.py --check
$gw = (Get-Command gw_sh.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if (-not $gw) { $gw = Get-ChildItem 'C:\Gowin' -Recurse -Filter gw_sh.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }; if (-not $gw) { throw 'Gowin not found' }
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2u\boards\a2n20v2-Enhanced
@('open_project a2n20v2_enhanced.gprj','run all','exit') | & $gw
Get-Item .\impl\pnr\a2n20v2_enhanced.fs | Select-Object FullName,Length,LastWriteTime
Select-String -Path .\impl\pnr\a2n20v2_enhanced_tr_content.html -Pattern 'Violated|Fmax|TNS' | Select-Object -First 30
openFPGALoader -b tangnano20k .\impl\pnr\a2n20v2_enhanced.fs
\`\`\`

Check timing and compilation before SRAM programming. Do not flash the FPGA
persistently until hardware audio is accepted.

## The isolation experiment

Without starting \`SENSEI8.SYSTEM\`, use HDMI USB keyboard TAB and
open \`MOD LIBRARY\` in Native DOC mode. Select audition mode using
LEFT/RIGHT, then choose a .MOD through \`MODS\` on the FAT32 volume.
After each selection change, STOP and reselect the same song.
Record the same HDMI volume and signal chain for all:

1. **ALL 4**: compare P2U corrected vibrato with P2T and VLC.
2. **CH1 RIGHT**: isolates short instrument 6/7/8 one-shots.
3. **CH2 RIGHT**: isolates long/sustained instrument 5, 4, 3, 8
   and vibrato/portamento.
4. **RIGHT 1+2**: should be the stereo right output with no left notes.
5. Optionally **CH0 LEFT** and **CH3 LEFT** for balance.

After each recording, capture the lines:
\`P2U FPGA OVR=... HIGH=... LATE=...\`,
\`P2U MCU SENT=... HIGH=...\`,
\`P2U MCU LATE=... MAXMS=...\`,
\`P2U NOTES CH0=... CH1=...\`,
\`P2U NOTES CH2=... CH3=...\`,
\`P2U AUDITION=... MASK=...\`.

Those counters prove tracker processing and transport; they do not prove
that each oscillator actually generated audio. If CH2 solo produces holes
where the source should sustain, the next focused release should instrument
FPGA **oscillator 4/5** WAV fetch, control state, halt reason, and
sustain SWAP. If CH2 produces correct sustain but the summed right remains
weak, inspect DOC right mixer and per-oscillator volume instead.

## Current limitations

Four-channel ProTracker MOD, <=64KiB source file, <=49KiB DOC PCM,
individual <=8KiB DOC wave. Arbitrary non-power-of-two loops remain
approximate; this test does not solve them. Hardware playing P2U not yet
verified. Keep standalone MilkyPlay/libxmp-lite PCM backend as fallback,
not as a reason to discard Native DOC compatibility.
