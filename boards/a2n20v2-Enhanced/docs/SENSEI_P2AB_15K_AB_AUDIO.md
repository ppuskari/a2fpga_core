# SenseiPlay8 P2AB — 15k NTP vs PT2 reference audit

**Status: experimental MCU-only NTP arpeggio correction; not yet hardware
validated.** Builds from P2AA Native-NTP-only. No HDL or PCM sample bank
change in P2AB. All ROM/FPGA assets and the August DOC SWAP fix remain as
in P2Y / P2AA. Do not overwrite the known-good FPGA flash.

## Actual recordings and original source

User A/B WAV `15kpcmntpandpt2.wav` is 136.377 sec, signed 16-bit 44.1 kHz
stereo. P2AA first song starts at about 1.67 sec and ends at 66.68 sec;
a ~2.93 sec quiet separator precedes PT2 at about 69.61 sec.
Measured active-song stereo RMS:
- P2AA: left .1973, right .1001.
- PT2:  left .1328, right .0638.
No full-scale clipping in the recording. P2AA is approximately 3.8/4.1
dB louder in L/R than PT2; apply gain normalization for listening A/B.

The user's `15k.ntp` v2 metadata: 4 tracks, 13 original instrument
records, 6 patterns, 6 orders. Original output assignments 1,0,0,1
are now correct in P2AA. The song contains 47 `0xy` arpeggio pattern
events, including **8 without a new note/instrument on channel 2**.

NinjaTrackerPlus 65816 reference:
https://github.com/antoinevignau/source/blob/master/ntpsources/ninjatrackerplus.s

- `setup_arpeggio`: if `0xy` has no note, uses last arpeggio root
  note and plays it again on the row's first tick.
- `handle_arpeggio`: invokes `check_play_note` on effect ticks to
  retrigger the DOC oscillators for root, +X, +Y semitones.
- P2AA instead only wrote DOC frequency registers during arpeggio ticks,
  and omitted the tick-zero note-less restart.
- P2AB restores both exact *control-flow behaviors* without changing
  pitch formulas or native sample bytes.

## Sustain audit

Most 15k lead/loop instruments use type 2 attack into a type 7
optimal free-running loop (B FREE); a lesser-used type 2 into type 3
uses the nonideal IRQ+SWAP retarget. P2Y's original HDL test validated
only the latter. P2AB adds `tb_p2ab_ideal_sustain.sv` using the real
`doc5503.sv` state machine to ensure:
- Attack A SWAP ends and starts partner B FREE.
- B remains RUN, with correct WTP/RTS and advancing accumulator.
- A stays halted, and normal FPGA SWAP logic is preserved.

**Passing HDL state tests do not prove audible sustain fidelity** on
hardware, SDRAM fetch timing, converter loop quality, or HDMI output.
Use the existing FPGA diagnostic overlay's DOC memory-fetch timeout/
late-response fields during real playback if sustain holes remain.

## Windows PowerShell 5.1 — paste each command on its own line

### Checkout

```powershell
$hw = 'C:\AppleIIgsDev_02\a2fpga-sensei-p2ab'
if (-not (Test-Path "$hw\.git")) { git clone --branch petar/sensei8-p2ab-ntp-arp-sustain-audit-20261120 --single-branch https://github.com/ppuskari/a2fpga_core.git $hw }
git -C $hw fetch origin petar/sensei8-p2ab-ntp-arp-sustain-audit-20261120
git -C $hw switch petar/sensei8-p2ab-ntp-arp-sustain-audit-20261120
git -C $hw pull --ff-only origin petar/sensei8-p2ab-ntp-arp-sustain-audit-20261120
git -C $hw log -1 --oneline
```

### Gowin GUI and ROM assets

**Not required in P2AB.** FPGA HDL and audio ROM assets are unchanged
from P2AA/P2Y. If FPGA SRAM has been cleared by power cycling, reload
the previously built P2Y FPGA bitstream using the Gowin GUI into
**volatile SRAM**, not persistent flash.

### MCU Stage 2 compilation

```powershell
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
Get-Item "$env:BL_SDK_BASE\project.build"
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host"
make -j4 CHIP=bl616 BOARD=bl616dk
if ($LASTEXITCODE -ne 0) { throw 'P2AB MCU build FAILED; do not flash' }
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
Get-FileHash .\build\build_out\a2n20_bl616_host_bl616.bin -Algorithm SHA256
```

### MCU Stage 2 only, preserve signed boot chain

```powershell
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616"
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

Never `make flash`: signed Stage1 at 0x0 must remain untouched.
Stage2 application is at 0x40000.

## Hardware acceptance order

1. Native DOC mode, P2Y FPGA in SRAM, select 15k.ntp.
   Expect OSD `SENSEI P2AB: NTP V2 ARP/LOOP AUDIT`.
2. Compare melody runs in the later half, especially channel 2's
   empty-note `0xy` blocks (around orders 3–5).
3. Compare original first-attack and later sustain, separately; P2AB
   is *not* a hardware sustain correction.
4. Audition PAIR 1+2 (right) versus PAIR 0+3 (left). Keep hardware
   counters from STOP: FPGA OVR/HIGH/LATE and MCU LATE/MAXMS.
5. Observe DOC memory-fetch timeout and late-response diagnostics in
   the existing FPGA debug overlay during choppy passages.
6. Compare both to the PT2 reference at normalized playback levels.
7. Retain the previous P2AA build and revert if melody gets choppier.

The user-uploaded WAV and NTP songs are not committed to this repo.
