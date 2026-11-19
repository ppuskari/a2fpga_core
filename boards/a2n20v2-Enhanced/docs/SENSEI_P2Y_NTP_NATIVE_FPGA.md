# SenseiPlay8 P2Y — native NinjaTrackerPlus C replayer + DOC waveform-end assist

**Status:** Development branch; requires both FPGA + BL616 Stage 2 builds.
Do not replace a working persistent FPGA flash image until regression tests,
full Gowin timing, and real Apple IIe playback are verified.

- Branch: `petar/sensei8-p2y-native-ntp-fpga-retarget-20261119`
- Parent: `petar/sensei8-p2x-ntp-stereo-parity-20261119`
- Hardware: a2n20v2-Enhanced Tang Nano 20K, BL616 host, 128K Apple IIe
- No Stage 1, no 6502 ProDOS SYS, no AY/SSI/A3 audio personality edits.

## Why this is a *new player* instead of another NTP-to-MOD importer

P2V/P2W copied authentic NinjaTrackerPlus DOC sample bytes but decoded the
NTP score into ProTracker bytes and ran P2U's generic effect interpreter.
That approach also used a paired DOC SWAP approximation which could replay
a nonideal split instrument's attack on every sustain round trip.

P2Y uses the ORIGINAL raw four-byte NTP pattern events:
`note, NTP instrument record, effect, argument`. There is now an
independent `sensei_ntp_native.c` row/tick scheduler, channel state,
instrument-only retrigger semantics, effect handlers and song flow.
The NTP -> DOC waveform importer is still deliberately byte-for-byte.
The regular `.mod` path remains on the prior P2U player.

Current subset: 4-track NTP v0/v2, no streaming, zero instrument finetune,
NTP effects `0,1,2,3,4,5,6,A,B,C,D,F,E6,E9,EC,ED`.
Full fidelity with the original NTP 65816 pitch lookup tables, other
E-effects, larger multichannel layouts and streaming is future work.
P2Y is not yet feature-complete NinjaTrackerPlus or hardware verified.

## FPGA special handling: exact first-end attack-to-sustain transition

Reference implementation:
https://github.com/antoinevignau/source/blob/master/ntpsources/ninjatrackerplus.s
`generate_osc_2` and the non-timer part of `interrupt_handler`.

For a type-2 (attack) followed by type-3 (sustain) with a nonideal sustain:
1. The MCU starts A with `CTRL = pan | 0x0E` (IRQ + SWAP, RUN)
   and B with `CTRL = pan | 0x07` (SWAP, HALT).
2. On the attack's original DOC zero-byte/end event, the **existing
   August SWAP FSM** halts A, starts B and resets B's accumulator.
3. **Only while Native DOC tracker ownership is active**, a new two-state
   assist reads the partner B's WTP/RTS and writes them to the halted A,
   clearing A's IRQ bit and retaining SWAP + HALT.
4. When B completes, it restarts A at the sustain sample, NOT the attack.
   The same two sustain waveforms can alternate indefinitely.
5. Normal MOD/Mockingboard SWAP never uses this assist. It is gated on
   tracker ownership **AND** the special `IRQ|SWAP` request signature.

Important: this is native FPGA assistance, **not yet** full guest-visible
DOC `$E0` interrupt-register emulation. An authentic IIgs 65816 interrupt
handler would require separate architectural work.

### August fix audit

The validated 2026-08-16 baseline at commit `f692c09acf57` has the
EXACT SAME Git blob for `hdl/sound/doc5503.sv` as the P2X November parent:
`66c0d8ab24cba366b83f05071ccb0fa8133f3f87`.
The August implementation already separates `OSC_HALT_ONE_SHOT_OR_ZERO_BYTE`
from `OSC_START_PARTNER` to avoid address/write arbitration races and
restarts the partner accumulator. P2Y leaves this original behavior intact.

### CI regressions

- `test_p2y_ntp_native.c`: NTP original raw-score note starts, stereo
  assignment, DOC volume 0..255, special 0x0E/0x07 instrument state,
  instrument-only retrigger, arpeggio release, E9/EC/ED, Fxx, Dxx.
- `tb_p2y_ntp_retarget.sv`: real `doc5503.sv` oscillator FSM:
  verifies disabled assist leaves SWAP behavior alone and enabled assist
  copies partner WTP+RTS and changes A control to sustain SWAP.
- Existing P1D, P2S, P2T, P2U, P2V and P2W portable regression steps remain.
- The TWO real NTP files are deliberately not committed to GitHub.

## Windows PowerShell 5.1 — source, assets, builds

Paste each command on its own line (new isolated copy):

```powershell
$hw = 'C:\AppleIIgsDev_02\a2fpga-sensei-p2y'
if (-not (Test-Path "$hw\.git")) { git clone --branch petar/sensei8-p2y-native-ntp-fpga-retarget-20261119 --single-branch https://github.com/ppuskari/a2fpga_core.git $hw }
git -C $hw fetch origin petar/sensei8-p2y-native-ntp-fpga-retarget-20261119
git -C $hw switch petar/sensei8-p2y-native-ntp-fpga-retarget-20261119
git -C $hw pull --ff-only origin petar/sensei8-p2y-native-ntp-fpga-retarget-20261119
git -C $hw log -1 --oneline
```

Generate/check the same known-good SynthLab piano and SSI263 voice ROM assets
(in this isolated worktree), before Gowin synthesis:

```powershell
Set-Location $hw
py -3 .\tools\extract_synthlab_piano.py --download
py -3 .\tools\extract_synthlab_piano.py --check
py -3 .\tools\generate_ssi263_voice.py
py -3 .\tools\generate_ssi263_voice.py --check
py -3 .\tools\generate_ssi263_p8_roms.py --check
py -3 .\tools\generate_ssi263_p9_nas_rom.py --check
py -3 .\tools\generate_ssi263_p9_output_fir.py --check
```

Gowin full rebuild (this time **required**, unlike P2W):

```powershell
$gw = (Get-Command gw_sh.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if (-not $gw) { $gw = Get-ChildItem 'C:\Gowin' -Filter gw_sh.exe -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }; if (-not $gw) { throw 'Gowin gw_sh.exe not found' }
Set-Location "$hw\boards\a2n20v2-Enhanced"
@('open_project a2n20v2_enhanced.gprj','run all','exit') | & $gw
Get-Item .\impl\pnr\a2n20v2_enhanced.fs | Select-Object FullName,Length,LastWriteTime
Select-String -Path .\impl\pnr\a2n20v2_enhanced_tr_content.html -Pattern 'Violated|Fmax|TNS' | Select-Object -First 30
```

MCU Stage 2 cross-build:

```powershell
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host"
make -j4 CHIP=bl616 BOARD=bl616dk
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
Get-FileHash .\build\build_out\a2n20_bl616_host_bl616.bin -Algorithm SHA256
```

### Deploy only after CI, cross-build, and Gowin timing pass

Load FPGA into **volatile SRAM** first; leave working FPGA flash untouched.
Then program only BL616 **Stage 2 at 0x40000**:

```powershell
Set-Location "$hw\boards\a2n20v2-Enhanced"
openFPGALoader -b tangnano20k .\impl\pnr\a2n20v2_enhanced.fs
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616"
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

**Never** run `make flash` (would overwrite signed Sipeed Stage 1 at
0x0). Do not use `openFPGALoader -f` until hardware audio is accepted.

## Targeted hardware A/B validation

Use the existing working `SENSEI8.SYSTEM`/ProDOS boot image, Native DOC mode
and same HDMI capture chain:

1. Native `15k.ntp`: confirm `SENSEI P2Y: NTP V2 NATIVE C/FPGA`.
2. Native `1_minute_dead_waltz.ntp`: note `Fxx` tempo changes, pattern
   loops, row breaks and order count.
3. Compare `15k.mod` via unchanged P2U MOD path.
4. Check stereo mapping: 15k NTP track output `1,0,0,1`; our DOC
   control bit 4 = physical left, output zero = right.
5. Audition individual CH0..CH3 to localize any remaining note dropout,
   particularly right-hand notes.
6. Compare instrument attack/sustain continuity and fast arpeggio passages.
7. At STOP/END capture FPGA OVR/HIGH/LATE, MCU SENT/HIGH/LATE/MAXMS,
   NOTES CH0..CH3. **OVR must be zero**.
8. Cold boot to verify the A3 persistent audio mode remains unchanged.

No hardware playback, full BL616 SDK cross-build, or Gowin timing closure
is claimed solely by the portable CI tests.
