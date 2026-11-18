# SenseiPlay8 P2R — DOC Attack/Sustain Fidelity Revision

Status: **source + CI tested; physical playback not yet validated**.
Branch: \`petar/sensei8-p2-attack-sustain-20261118\`.
Based on the first hardware-working runtime MOD file picker:
\`petar/sensei8-p2-playable-20261118\`.

No changes to the 6502 ProDOS launcher or FPGA RTL. The original generic
P2 ProDOS 2.4.3 \`SENSEI8.SYSTEM\` disk remains compatible. Keep the
hardware-proven P2 bitstream and MCU backup until this revision plays
correctly on your Apple IIe.

## What changed

- The original MOD samples are parsed **at runtime**, just as P2 did.
  No generated song executables, precomputed effect timelines or embedded
  MOD patterns.
- Full attack content is preserved. Previously, the P2 decoder discarded
  everything before the sustain-loop start and padded the remaining
  waveform with silence.
- For samples with a nonzero loop start, the decoder allocates two DOC
  waveforms: full one-shot attack (MODE_SWAP) and a separate looped
  sustain (MODE_FREE).
- A zero-byte terminator at the *true* MOD loop-start location makes the
  DOC's built-in swap hardware start the sustain partner, sample-accurately.
  No MCU timer, polling or offline note effects are used to switch.
- Four MOD channels map to eight physical DOC oscillators:
  tracker 0 -> DOC 0/1 LEFT; tracker 1 -> DOC 2/3 RIGHT;
  tracker 2 -> DOC 4/5 RIGHT; tracker 3 -> DOC 6/7 LEFT.
  These are **not** a change to the global HDMI stereo wiring.
- Pitch effects, volume changes and note retriggers operate on both
  members of each pair, so no old sustain survives a new note.
- STOP and end-of-song mute all eight oscillators, rather than the
  old first four.
- The P2 runtime-start sequence explicitly sets DOC enable register
  $E1=$3E (32 enabled oscillators), restoring the oscillator scan rate
  required by the proven FC=69013/period frequency formula.
- The original P1D synthetic tracker and P2 FAT32 file picker, DMA ACK,
  Mockingboard SynthLab piano and SSI263 voice code are unchanged.

### 15k Boogie, instrument audit

| Instrument | Original PCM | Attack | Original sustain loop |
|---|---:|---:|---:|
| 1 | 942 bytes | 814 bytes | 128 bytes |
| 15 | 990 bytes | 862 bytes | 128 bytes |

Before: only the last 128 bytes of each of these instruments were
repeated into a 256-byte waveform, with 128 bytes silence at the end.
After: both original attacks are preserved in 1 KiB DOC waveform tables,
followed automatically by a 256-byte sustain table containing two exact
copies of the original 128-byte loop. The total 15k DOC instrument bank
is expected to be **11,520 bytes**; this is within the 49,152-byte
runtime sampler limit and 64 KiB DOC bank 0.

Small non-power-of-two MOD loops (e.g. 24 bytes) still need approximation
in the DOC backend because its waveform lengths are powers of two.
Likewise an arbitrary sample longer than 8 KiB can be rejected. The
future software PCM mixer is the right place for sample-exact arbitrary
loop points, interpolation and effects.

## Windows PowerShell 5.1 — one command per paste

Use an *isolated* new checkout so the previously playable P2 firmware
and bitstream are untouched:

```powershell
$hw = 'C:\AppleIIgsDev_02\a2fpga-sensei-p2r'
if (-not (Test-Path "$hw\.git")) { git clone --branch petar/sensei8-p2-attack-sustain-20261118 --single-branch https://github.com/ppuskari/a2fpga_core.git $hw }
git -C $hw fetch origin petar/sensei8-p2-attack-sustain-20261118
git -C $hw switch petar/sensei8-p2-attack-sustain-20261118
git -C $hw pull --ff-only origin petar/sensei8-p2-attack-sustain-20261118
git -C $hw log -1 --oneline
```

Prepare the unchanged SynthLab and SSI263 audio ROMs before Gowin:

```powershell
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2r
py -3 tools\extract_synthlab_piano.py --download
py -3 tools\extract_synthlab_piano.py --check
py -3 tools\generate_ssi263_voice.py
py -3 tools\generate_ssi263_voice.py --check
py -3 tools\generate_ssi263_p8_roms.py --check
py -3 tools\generate_ssi263_p9_nas_rom.py --check
py -3 tools\generate_ssi263_p9_output_fir.py --check
(Get-Content .\boards\a2n20v2-Enhanced\hdl\piano_multisustain.mem | Measure-Object -Line).Lines
(Get-Content .\boards\a2n20v2-Enhanced\hdl\ssi263_voice.mem | Measure-Object -Line).Lines
```

Expected piano 1,408 ROM words; legacy SSI263 voice 8,192 bytes.
The latest hybrid SSI263 voice remains synthesized by the BL616 from
its existing checked-in Pico-derived C source.

Gowin (assumes installed under \`C:\Gowin\` if not already on PATH):

```powershell
$gw = (Get-Command gw_sh.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if (-not $gw) { $gw = Get-ChildItem 'C:\Gowin' -Filter gw_sh.exe -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }; if (-not $gw) { throw 'Gowin gw_sh.exe not found' }
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2r\boards\a2n20v2-Enhanced
@('open_project a2n20v2_enhanced.gprj','run all','exit') | & $gw
Get-Item .\impl\pnr\a2n20v2_enhanced.fs | Select-Object FullName,Length,LastWriteTime
Select-String -Path .\impl\pnr\a2n20v2_enhanced_tr_content.html -Pattern 'Violated|Fmax|TNS' | Select-Object -First 30
```

BL616 Stage 2 **host** firmware (requires Bouffalo SDK 2.3.27, GNU
make and T-Head RISC-V gcc on PATH):

```powershell
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
Get-Item "$env:BL_SDK_BASE\project.build"
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2r\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
make -j4 CHIP=bl616 BOARD=bl616dk
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
Get-FileHash .\build\build_out\a2n20_bl616_host_bl616.bin -Algorithm SHA256
```

Hardware programming must wait for *both* full FPGA and MCU builds to
pass. **Never run \`make flash\`** (the BL616 is fused; Stage 1 at 0x0
must remain intact). First use volatile FPGA SRAM load:

```powershell
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2r\boards\a2n20v2-Enhanced
openFPGALoader -b tangnano20k .\impl\pnr\a2n20v2_enhanced.fs
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2r\boards\a2n20v2-Enhanced\src\a2n20_bl616
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

Reprogram volatile FPGA SRAM after a power cycle / BL616 update, as
needed. Make FPGA flash persistent with openFPGALoader -f **only
after** first physical recordings pass.

The 6502 player and ProDOS \`.po\` disk are **unchanged** from P2:

- Repository \`ppuskari/SenseiPlay8\`, branch
  \`petar/p2-runtime-controller-20261118\`
- \`py -3 tools\make_p2_runtime_sys.py\`
- \`py -3 tests\test_p2_runtime_sys.py\`
- Bootable conversation image:
  \`SenseiPlay8-P2-RuntimeMOD-ProDOS243.po\`.

The MODs remain ordinary files in the FAT32 SD card's \`MODS\` folder.
Select **STORAGE → SD ONLY → RESCAN / REMOUNT ALL** when required.
Launch \`SENSEI8.SYSTEM\` in ProDOS, then TAB on the HDMI USB keyboard,
MOD LIBRARY, browse MODS, choose 15k and then Dead Waltz. Compare HDMI
stereo WAVs with VLC. Do not reverse the global L/R wiring.

## Validation gate

- Portable C regression recreates the 814/128 and 862/128 split as
  **original synthetic data**, preserving user's original PCM privately.
- C test validates exact waveform bytes at the attack, zero sentinel at
  each loop start, repeated 128-byte sustain, DOC WTP/RTS/SWAP settings,
  mirrored effects, and four-channel stereo routing.
- Existing P1D/P1E/P2 parser, FAT32 broker, PCM DMA, FPGA SPI, STOP,
  timing and runtime tests still run in CI.
- **Physical SoundLab/Mockingboard and 15k/Waltz audio are not yet tested
  on this revision.** Do not call P2R a new golden until both recordings,
  cold boot, STOP and reselection have been validated.
