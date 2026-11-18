# SenseiPlay8 P1D: first BL616/FPGA offloaded tracker protocol

Status: **development branch only**. SV mailbox simulation and portable MCU-C
compilation are validated. No claim of physical FPGA timing, full Gowin
place-and-route, or flashed BL616 firmware validation yet.

Base: `petar/audio-m641-a3-hwvalidated-20261117`.
Feature: `petar/sensei8-p1d-mcu-fpga-20261118`.

## Hardware ownership and compatibility

- Enhanced Native DOC audio personality A2 (or Shared A3) must be active.
- Slot 4 native DOC registers `$C0C0..$C0C9` remain unchanged.
- New IIe-only mailbox is `$C0CA..$C0CF` on that same virtual slot.
- FPGA observes `$C0CC` command writes and increments a sequence counter.
- MCU polls via SPI **XFER space 6**. Spaces 4 and 5 remain SSI263.
- Original IIGS DOC `$C03C..$C03F` and Mockingboard mode are not redirected.
- MCU explicitly claims exclusive DOC-register control using SPACE6:0x16=1.
- IIe uploads test waveform data before requesting START. Concurrent
  CPU DOC register writes are blocked while MCU owns DOC. The FPGA plays
  a deadline-ordered queue; no shared DOC register writers at once.
- The dedicated DOC Sound-RAM DMA path is **not part of P1D**. Do not
  access the shared SDRAM blindly from MCU XFER SPACE1; this could
  overwrite unrelated Apple/FPGA memory.

## IIe mailbox

| Slot 4 address | CPU reads | CPU writes |
|---|---|---|
| `$C0CA` | `$53` ('S') | ignored |
| `$C0CB` | `$1D` protocol revision | ignored |
| `$C0CC` | MCU state: 0=idle, 2=playing, 3=done, 4=error | command 1=START, 2=STOP |
| `$C0CD` | host command sequence byte | song ID (0 for P1D demo) |
| `$C0CE` | FPGA FIFO occupancy | ignored |
| `$C0CF` | saturating FIFO overflow count | ignored |

Always write ARG at `$C0CD` **before** CMD at `$C0CC`.
Never issue a second START while busy. Any key sends STOP and waits
for MCU acknowledgment before the IIe writes any DOC registers.

## MCU SPI XFER SPACE 6 register bytes

| Address | Direction | Meaning |
|---|---|---|
| 00 | R | `$53` signature |
| 01 | R | `$1D` protocol revision |
| 02 | R | last IIe command |
| 03 | R | IIe command sequence |
| 04 | R | song ID argument |
| 05 | R/W | state |
| 06 | R | FIFO occupied slots |
| 07 | R | saturating overflow count |
| 08–09 | R | 16-bit FPGA milliseconds counter, little-endian |
| 0A–0B | R | 16-bit completed DOC write count |
| 0C | R | bit 0=native enabled, bit 1=MCU DOC owner |
| 10–11 | W | staged absolute 16-bit deadline milliseconds |
| 12 | W | staged DOC register address |
| 13 | W | staged DOC register value |
| 14 | W | **commit** with `$A5` |
| 15 | W | **flush queue** with `$A5` |
| 16 | W | bit 0: claim/release exclusive DOC ownership |

Upload a five-byte event with one XFER from address `$10`:
`[deadline_lo, deadline_hi, doc_address, doc_data, $A5]`.
The queue preserves submission order for equal deadlines, so MCU
must enqueue deadlines in chronological order. The FPGA expires one
queued event per 54 MHz clock and clocks the DOC core on the following
cycle. Timing resolution is 1 ms; every 16-bit timestamp wraps after
65.536 seconds and must be scheduled within 32.768 seconds of now.
The MCU limits its lookahead to ~80 ms.

FIFO: 64 entries (synthesis parameter `FIFO_AW=6`). When full,
commits are discarded and the overflow counter increments. The
MCU checks occupancy before issuing each tick's batch.

## P1D demonstration

The IIe ProDOS SYS is built by `SenseiPlay8/tools/make_p1d_sys.py`.
It uploads the same four 256-byte eight-cycle DOC tables proven with
P0P8 (sine, triangle, pulse, bell). The BL616 task starts on command 1
(song ID 0) and generates 192 rows at six 20-ms ticks per row:
note-on chords, ch0 arpeggio, ch3 vibrato, ch1 volume slide, stereo
routing via DOC control channel bit4. The IIe remains in a status/key
polling loop. MCU flushes and silences the voices before releasing DOC.

Full ProTracker sample loading, pattern parsing, effect parity, native
NTP decoding, MCU->DOC Sound-RAM DMA, and high-rate tick interpolation
are future versions. Do not describe P1D as a fully offloaded MOD
file player yet.


## Before Gowin: regenerate all Mockingboard audio assets (PowerShell 5.1)

Run each command individually in the NEW a2fpga P1D worktree, not the
working P1B/P1C SenseiPlay8 repository:

```powershell
cd C:\AppleIIgsDev_02\a2fpga-sensei-p1d
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

Expected line counts: 1408 piano words, 8192 legacy voice bytes.

**SynthLab sustain bank:** The genuine System 6.0.4 SynthLab
`synthLAB.po` disk is downloaded (or provided locally using
`--disk 'C:path	osynthLAB.po'`). The extractor verifies disk MD5
`fa4f143dd899d0cc4c8ed9c9e41b7d37`, all seven sampled
sustain-zone hashes, and final packed FNV32 `170BB8B3`. Generated
ROM `hdl/piano_multisustain.mem` is 5632 bytes (1408 32-bit
words). The source Apple PCM cannot be checked into the repository.
The existing Enhanced Gowin `prebuild.tcl` will also
attempt this extraction if the file is missing and always checks the
fingerprint, but explicit generation catches network problems early.

**Legacy SSI263 PCM bank:** `generate_ssi263_voice.py` creates
`hdl/ssi263_voice.mem`, an original *approximate* bank of
64 x 128 8-bit phonemes, used only if the legacy FPGA renderer is
selected. The current P10 hybrid voice is NOT that wavetable: it is
synthesized live in C by the BL616, using
`reference/ssi263/pico-v1.0.1/ssi263.c` plus
`ssi263dsp.c` compiled in the host firmware. P8/P9 FPGA
ROMs are checked in; the `--check` commands verify them.

**FX percussion samples:** `tools/build_mb_doc_fx_bank.py` is
an independent test bank generator in this branch. Its
sample-preload/one-shot integration is NOT part of this P1D feature.
The experimental M65/M66 sampled-FX development is on separate
branches and must not be assumed included merely because
`build_mb_doc_fx_bank.py` exists.

These assets support **Enhanced Mockingboard mode**, whereas P1D's
native-DOC test song uploads its own four P0P8 256-byte samples from
`SENSEI8.SYSTEM` and does not require the Apple SynthLab bank
for its original 192-row demonstration.

Proceed with new Gowin synthesis/place-and-route only after these
checks all pass. Do not build new gateware from stale/missing .mem files.

## Rollout and rollback

1. Preserve the known-good physical FPGA/MCU binaries and flash images.
2. Verify Synth P1D Icarus + C syntax + source wiring CI.
3. Build the new FPGA through the existing Gowin project file
   (`boards/a2n20v2-Enhanced/a2n20v2_enhanced.gprj`).
4. Build the paired host-mode BL616 Stage 2 firmware, honoring the
   established Stage 2 offset `0x40000` and the board's flash workflow.
5. Flash FPGA and MCU as a matching pair, **only after both builds pass**.
   If only one side is new, do not run the P1D SYS.
6. Check for mailbox `$53/$1D` at `$C0CA/$C0CB` in A2 mode.
7. Test the P1D ProDOS demo, inspect the FIFO overflow and completion
   status, and validate output with a stereo recording.
8. For rollback, restore **both** previously working FPGA and MCU images.

The feature branch does not change any persisted audio personality
setting. P1D is dormant until Native DOC is active and a IIe START arrives.
