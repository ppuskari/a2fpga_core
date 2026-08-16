# A2FPGA Enhanced forced-legacy-64K A/B test

This source set starts from the working
`A2FPGA-Enhanced-Oscillator-Mix-Diagnostics` checkpoint and makes one bounded
functional change: the `a2n20v2-Enhanced` build is forced into native
IIgs-compatible 64K DOC waveform-RAM behavior.

## Why this build exists

The Music Studio 2.0 diagnostic capture showed `$C03C = $35` while many
oscillators reached `OSC_MIX`, most produced silence, and all waveform-read
error counters stayed at `$00`. The A2FPGA 128K extension had repurposed
`$C03C` bit 4 as the upload-bank selector. An actual bank-1 write enabled RTS
bit 6 as the playback-bank selector.

Legacy Music Studio sets those bits for its own native-IIgs operation. The
extension could therefore place ordinary samples in bank 1 and select
inconsistent playback banks, producing silence, stale samples, wrong
instruments, and distortion.

## Exact source changes

### `hdl/sound/sound_glu.sv`

Added the shared parameter:

```systemverilog
parameter bit FORCE_LEGACY_64K = 1'b0
```

When it is true:

- the effective CPU upload bank is always bank 0;
- upper-bank writes cannot latch `sound_128k_enable_r`;
- the effective DOC playback bank is always bank 0;
- `$C03C` storage, readback, volume, RAM/DOC access selection, and
  auto-increment behavior are unchanged.

The parameter defaults to false, preserving every other existing
`sound_glu` instantiation.

### `boards/a2n20v2-Enhanced/hdl/top.sv`

The Enhanced board instance now supplies:

```systemverilog
.FORCE_LEGACY_64K(1'b1)
```

This is the only board on which the A/B override is enabled.

### Documentation

Added `boards/a2n20v2-Enhanced/docs/DOC_FORCED_LEGACY_64K_AB_TEST.md` and linked
it from the Enhanced board README.

## What remains unchanged

- The raw Sound GLU debug byte remains the actual `$C03C` value. Music Studio
  should continue to show `$35`.
- The oscillator-output, `OSC_MIX`, channel-mask, completed-mix history, read
  overlap, timeout, and late-response diagnostics all remain visible.
- `doc5503.sv` is byte-for-byte unchanged from the preceding checkpoint.
- No oscillator, mixer, gain, saturation, HDMI, or SDRAM transaction logic is
  otherwise changed.

## Hardware test procedure

1. Extract the changed-files ZIP over the project root.
2. Rebuild `boards/a2n20v2-Enhanced/a2n20v2_enhanced.gprj`.
3. Confirm place-and-route timing is clean before flashing.
4. Flash the newly generated `.fs` and power-cycle/reset the IIgs.
5. Start the same Music Studio 2.0 jukebox song from its beginning.
6. Compare native DOC and HDMI output while recording the overlay.

Confirmation criteria:

- full, correct HDMI music begins with the native playback;
- the correct instruments are heard rather than distorted or stale samples;
- both stereo channels behave normally;
- nonzero-oscillator activity substantially matches mixer activity;
- left/right completed-mix histories reflect the song; and
- all three read-path error counters remain `$00`.

The visible `$C03C` field should still be `$35`; the build ignores only the
banking meaning of bit 4.

## Deliberate limitation

The 128K extension is disabled on Enhanced in this checkpoint. Tool225 and
the 128K sample-RAM harness cannot use bank 1 until the override is removed or
replaced by the planned explicit unlock protocol.

## Validation boundary

- Parsed all 106 SystemVerilog files with the same result as the input
  oscillator/mix diagnostic checkpoint: 104 clean files and the same two
  pre-existing grammar findings. `sound_glu.sv` parses cleanly, and the
  Enhanced `top.sv` retains only its prior conditional/preprocessor finding.
- Exhaustively checked the A/B bank truth table for both values of the force
  parameter, `$C03C` bit 4, and RTS bit 6. Every forced-mode combination
  resolves to upload bank 0, leaves the 128K enable clear, and resolves to
  playback bank 0.
- Confirmed `doc5503.sv` is byte-for-byte unchanged from the tested input
  checkpoint.
- Confirmed the shared parameter defaults off and only the Enhanced board
  explicitly enables it.
- Both ZIP archives pass compressed-data integrity checks, and the
  changed-files archive uses project-root-relative extraction paths.

Gowin EDA is not available in this environment, so this package contains
source only. The `.fs` files inside the complete tree predate this A/B change.
Rebuild the Enhanced project and verify timing before flashing.
