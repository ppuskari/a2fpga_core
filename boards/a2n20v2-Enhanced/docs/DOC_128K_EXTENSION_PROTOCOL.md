# DOC 128K extension protocol version 1

The Enhanced core starts in strict Apple IIgs-compatible 64K DOC waveform-RAM
mode. Legacy software cannot select bank 1 merely by leaving reserved Sound GLU
bit 4 or oscillator wavetable-register bit 6 set.

## Why an unlock is required

Music Studio 2.0 writes `$35` and `$75` to `$C03C`. On a native IIgs, bit 4 is
reserved and has no banking effect. The original A2FPGA extension interpreted
that bit directly as the CPU upload-bank selector, causing Music Studio's
normal 64K waveform load to enter bank 1. Its oscillator RTS bit 6 values then
selected inconsistent playback banks, producing silence, wrong instruments,
and distortion.

The forced-64K A/B build restored complete Music Studio playback and proved
that this collision, rather than the DOC HALT-on-zero path, mixer, or SDRAM
timing, caused the failure.

## Command transport

Commands are five consecutive writes to otherwise-unused DOC register
addresses. Select DOC-register access in `$C03C`, set the DOC address pointer
to `$00E2`, and write the following bytes through `$C03D`:

| DOC address | Data | Meaning |
|---|---:|---|
| `$E2` | `$41` | ASCII `A` |
| `$E3` | `$32` | ASCII `2` |
| `$E4` | `$46` | ASCII `F` |
| `$E5` | `$50` | ASCII `P` |
| `$E6` | `$01` or `$00` | unlock or lock command |

The complete byte stream is therefore:

```text
41 32 46 50 01    unlock 128K mode
41 32 46 50 00    relock into native 64K mode
```

Auto-increment may be used, so a program needs only one pointer setup followed
by five data writes. A mismatched DOC data write, Sound-RAM data write, or
Sound GLU control write cancels an incomplete key. Writes to `$E2-$E6` are
consumed by the extension and are not forwarded to the DOC core.

## State rules

After reset or relock:

- `$C03C` bit 4 is ignored for banking;
- all CPU waveform uploads target bank 0;
- oscillator wavetable-register bit 6 is ignored for banking; and
- all waveform fetches target bank 0.

After a successful unlock:

- `$C03C` bit 4 selects the CPU upload bank;
- `$60` loads bank 0 and `$70` loads bank 1, preserving Antoine Vignau's
  original test convention; and
- oscillator wavetable-register bit 6 remains inactive until at least one
  byte has actually been written to bank 1.

After the first bank-1 write, wavetable-register bit 6 selects the playback
bank. A relock immediately forces uploads and playback back to bank 0 without
changing the visible `$C03C` register value. The contents of bank 1 are not
erased, but a later unlock requires a new bank-1 write before playback bank
selection becomes active.

Software using the extension should unlock immediately before its 128K load
and relock after stopping its oscillators. The program that unlocks the
extension owns the matching relock. Antoine follows that rule. Tool225 P0.7 is
a legacy 64K client and does not send protocol-v1 lock commands.

## Debug status

The final byte on the top hexadecimal overlay row reports:

| Value | State |
|---:|---|
| `$10` | Protocol version 1, locked |
| `$11` | Unlocked; bank 1 has not been written |
| `$13` | Unlocked; bank 1 has been populated and RTS bit 6 is active |

The expected Antoine test sequence is `$10 -> $11 -> $13 -> $10`. Music Studio
2.0 should remain at `$10` even though its `$C03C` field displays `$35` or
briefly `$75`.

