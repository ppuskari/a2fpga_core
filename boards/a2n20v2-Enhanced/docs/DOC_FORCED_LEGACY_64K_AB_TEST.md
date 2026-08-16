# DOC forced-legacy-64K A/B test

This historical Enhanced-board checkpoint tested whether Music Studio 2.0 was being broken
by an accidental collision between legacy Sound GLU use and the A2FPGA 128K
DOC extension.

The preceding oscillator-to-mixer diagnostic capture showed the following
combination:

- Music Studio held the native Sound GLU register at `$C03C = $35`;
- many oscillators executed `OSC_MIX`;
- most oscillator outputs were `$80` silence or had zero volume;
- waveform-read overlap, timeout, and late-response counts stayed `$00`;
- native DOC playback was full while HDMI playback was sparse and incorrect.

In the extension implementation, `$C03C` bit 4 selected the waveform-RAM
upload bank. A write to bank 1 then enabled interpretation of oscillator RTS
bit 6 as the playback-bank selector. Legacy Music Studio did not intend either
bit to have those meanings.

## Result

The A/B build restored complete, correct Music Studio playback immediately.
The `$C03C` bit-4 collision was therefore confirmed. The temporary
`FORCE_LEGACY_64K` parameter has been replaced by the permanent, reset-locked
[DOC 128K extension protocol](DOC_128K_EXTENSION_PROTOCOL.md).

## A/B override used by the historical build

The diagnostic source added a `FORCE_LEGACY_64K` parameter. Its default was
`0`, while the Enhanced board set it to `1` for the test.

With the override enabled:

1. Every CPU waveform-RAM write goes to bank 0, regardless of `$C03C` bit 4.
2. A legacy bit-4 write cannot set `sound_128k_enable_r`.
3. Every DOC waveform fetch comes from bank 0, regardless of RTS bit 6.
4. The raw `$C03C` debug field remains unchanged and should still display
   Music Studio's `$35` value.

The 128K implementation remains in the shared source; this build only masks
its bank effects at the Enhanced `sound_glu` instance.

## Music Studio 2.0 test procedure

Power-cycle or reset the IIgs, start the same Music Studio jukebox song, and
record both native DOC and HDMI from the beginning.

The observed confirmation was:

- HDMI becomes full and correct immediately instead of after roughly 49
  seconds;
- the intended instruments match the native DOC output;
- both HDMI stereo channels become active when the arrangement uses them;
- the top nonzero-oscillator row now follows the bottom `OSC_MIX` row much
  more closely;
- the channel-address mask and completed left/right histories show normal
  activity; and
- the three waveform-read diagnostics remain `$00`.

The top hexadecimal `$C03C` field should still show `$35`. That is intentional:
the test changes only the banking interpretation, not the emulated register.

## Historical limitation

That checkpoint deliberately disabled the 128K DOC extension on the Enhanced
board, so 128K-specific harnesses could not use bank 1. The permanent protocol
keeps the proven locked behavior while restoring bank 1 only after an explicit
unlock.

## Functional boundary

This checkpoint does not change oscillator scheduling, waveform pointers,
HALT, one-shot, SWAP, SYNC/AM, accumulators, stereo channel routing, mono
selection, mixer saturation, `TOP_BIT_OFFSET`, HDMI gain, clamps, or any of the
existing overlay diagnostics.
