# P4: MCS song articulation, rest markers, multisample piano and AY title effects

**Branch:** `petar/mb-doc-p4-mcs-articulation-rest-multisample-20261107`  
**Parent:** `petar/mb-doc-c3-pitch-calibration-20261106` (A440 validated with the 8 keyboard keys).  
**Status:** Experimental FPGA-only hardware build; Icarus/Verilator RTL tests are necessary but not a listening test or Gowin timing closure.

## Evidence from the user-provided DOS 3.3 `mockingboard1.dsk`

This analysis came directly from the supplied 143,360-byte disk; the disk itself is **not committed**. To recheck with your copy:

```powershell
py -3 tools\inspect_mockingboard_dos33.py C:\path\to\mockingboard1.dsk
```

1. `HELLO` loads `BLOCK GRAPHICS` as a binary at `$8000`, `SCROLL2` at `$8AFF`, `LETTER SHAPES` at `$6000`, and then calls `$8000`.
2. The `BLOCK GRAPHICS` title routine first writes an AY-register preset from **`$81EA`** to the left VIA/PSG at `$C400/$C401`: R7=`$38`, R8/R9/R10=`$10`, R13=`$08` (three tone channels with envelopes). Another preset at **`$81FA`** includes R7=`$07`, R6=`$10`, R8–R10=`$10` (noise-driven).
3. `$8168` initializes the left VIA timer-1 interrupt. Its timer latch is `$CF00` (~51.8 ms at an approximately 1.02-MHz 6502 peripheral clock). The IRQ routine begins at **`$8194`**, reads `$C404` to acknowledge Timer 1, then modifies an AY-register table at **`$81DA`**. Specifically it decrements R0 at `$81DA`, decrements R2 at `$81DC`, and increments R6 at `$81E0`, then calls `$80C0` to rewrite the 16 AY registers to the left chip. The initial R0/R2 values are `$F4/$E6`, R7=`$1C`, amplitudes R8/R9=`$0F`. The sweep stops when R0 reaches `$35`; the handler disables the timer interrupt and resets the PSG. These are timed glissando/noise effects synchronized to the title sequence, **not silent period-1 rest events**.
4. `MCS` is a separate 803-byte binary at `$8500`. Its note-period tables at `$8531` (low bytes) and `$8571` (high bytes) have note-table entries 62 and 63 both equal to **period `$0001`**. This is approximately 63.8 kHz on the original AY: an intentional ultrasonic marker, **not a piano note to resynthesize**. It may appear as rest-related song data; the driver’s exact treatment can depend on the event/control byte. The three song files `SUGAR2`, `MINUTE`, and `WEASEL` are 2304 bytes each.
5. `KEYBOARD` uses tone-A periods 244,217,193,182,162,145,129,122, mixer R7=`$3E`, R8=`$10`, and *re-writes R13* for each note. That native AY envelope produced the remarkable natural piano decay in the recording. In contrast MCS songs use software volume steps and do not routinely retrigger that R13 envelope.

**Conclusion:** Two independent problems require independent solutions: mute MCS period-1 sentinel tones, but render the title animation's real timer-driven AY effects through the original AY generator, not through a continuously looping piano oscillator.

## What P4 implements

### 1. Articulation for non-R13 music

The six-voice bridge now recognizes new notes per channel from:
- silence/rest to active tone,
- an AY tone-period change of at least 3.125%, distinguishing ordinary semitone motion from the title routine’s 1-count pitch sweep,
- a meaningful upward fixed-volume step of three of the 15 AY amplitude levels (a re-strike of the *same* pitch),
- a change of sampled piano zone.

On these new-note events the existing DOC voice receives HALT/WTP/RTS before frequency, volume and RUN, restarting the oscillator's sample phase. Fixed-volume notes also get a supplementary software one-shot volume decay; the original native YM envelope path remains unchanged for AY amplitude bit 4 (e.g. the excellent keyboard A440 notes).

This is a **piano interpretation mode**, not an AY-identical translation. Disable `MB_DOC_PIANO_ARTICULATION_ENABLE` in `top.sv` to compare without the supplementary decay.

### 2. Silence for period-0 and period-1 markers

If AY period `0` or `1` is encountered, the DOC voice volume becomes zero and CTRL HALT is issued, regardless of fixed AY volume. The frequency divider still saturates as before but the oscillator cannot emit high-rate PCM aliasing. On the next valid note it retriggers appropriately.

### 3. Seven authentic sampled sustain zones

`tools/extract_synthlab_piano.py --download` reads the **same checksum-verified Apple IIgs System 6.0.4 SynthLAB disk** and generates **one 5632-byte `piano_multisustain.mem`** (1408 little-endian 32-bit words). It does *not* include any copyrighted PCM bytes in GitHub. Each source sample's FNV is independently checked; combined FNV32 **`170BB8B3`**. Packed sound-RAM layout:

| Original waveform | Bytes | New DOC base | WTP | WTS |
|---|---:|---:|---:|---:|
| `~Piano C1` | 1024 | `$0000` | `$00` | 2 |
| `~Piano G1` | 1024 | `$0400` | `$04` | 2 |
| `~Piano E2` | 1024 | `$0800` | `$08` | 2 |
| **`~Piano C3`** | **1024** | **`$0C00`** | **`$0C`** | **2** |
| `~Piano B3` | 512 | `$1000` | `$10` | 1 |
| `~Piano F4` | 512 | `$1200` | `$12` | 1 |
| `~Piano D5` | 512 | `$1400` | `$14` | 1 |

`RES=0` and the A440-calibrated AY `FC=93623/P` formula remain unchanged. The DOC's active accumulator range depends on RES, while WTS controls how many addresses are sampled per cycle; these original sustains all have a substantial first spectral component.

**Conservative initial range mapping:** the *entire* demonstrated keyboard C4–C5 (AY periods 244 down to 122) continues using the authentic `~Piano C3`, preserving the tested timbre and pitch. Other zones are engaged by AY period thresholds 600,1000,1600 on low notes and 112,90,70 on high notes. These boundaries are a deliberately experimental musical choice, not a proven original SynthLAB instrument-map.

Disable `MB_DOC_MULTISAMPLE_ENABLE` in `top.sv` to compare the same P4 articulation with only the calibrated 1KB C3 sustain. The extractor still produces the complete sound-ROM so the address remains `$0C00` for C3.

### 4. Title/special-effects fidelity

The existing two native YM2149 cores remain active during MB-DOC mode. P4 adds a classifier and selects **DC-blocked native AY audio** instead of DOC audio, independently for left and right chips, whenever it sees active AY noise, the title routine’s two-tone fixed-volume sweep, or a three-channel envelope effect. This should retain the timer IRQ's original pitch/noise transients and event timing rather than replaying piano samples as letters land.

It does not modify VIA6522 IRQ, clock, or reset logic. The audio mux switches source at the AY write boundary without a crossfade; any transition click or stereo-level mismatch requires listening tests and possible smoothing.

## Build/test on Windows

```powershell
git clone --branch petar/mb-doc-p4-mcs-articulation-rest-multisample-20261107 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-p4
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-p4
py -3 tools\extract_synthlab_piano.py --download
```

Open `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj` in Gowin. Check `piano_multisustain.mem` was recognized, BRAM/resource usage, timing closure, DOC and YM audio ownership, then compile and flash the **FPGA bitstream only**. Never flash BL616 firmware as part of this test. Retain the last A440-calibrated `.fs` and the earlier modeled-piano P3 `.fs` for rollback.

**Suggested listening A/B:** (a) boot title letter effects, (b) keyboard A–K to confirm A440/decay, (c) SUGAR2 with and without P4 articulation, (d) a lower-range selection from MCS, (e) repeat all with FX bypass disabled to isolate the title improvement.

## Evidence and limitations

The existing CI test preloads all 1408 words, checks full PCM fingerprint and oscillator initializations, three RES settings, period-1 rest muting, re-strike after rest, same-pitch upward-amplitude re-strike, keyboard hardware-envelope behavior, PSG reset, and startup/glide/noise classifier. The YM2149 shape bench remains independent. The CI **does not** run Gowin P&R or generate actual HDMI audio: timing, audio levels, sample tuning in the outer zones, and title synchronization still require real IIe/FPGA hardware listening.
