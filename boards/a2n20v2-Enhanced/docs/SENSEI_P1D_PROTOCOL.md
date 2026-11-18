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
