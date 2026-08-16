# ADR 0002: Require an explicit unlock for the DOC 128K extension

- Status: Accepted
- Date: 2026-08-02

## Context

The Apple IIgs Sound GLU defines `$C03C` bit 4 as reserved. The first A2FPGA
128K waveform-RAM extension reused it directly as the CPU upload-bank select
and began honoring oscillator wavetable-register bit 6 after an upper-bank
write.

Music Studio 2.0 legitimately leaves reserved bit 4 set in its `$35/$75`
control templates. Direct interpretation therefore redirected its ordinary
64K waveform load and broke playback. A forced-bank-0 hardware test restored
correct Music Studio audio.

## Decision

Every `sound_glu` instance is native-compatible and locked after reset. Only
the Enhanced board enables protocol version 1. Software must write the exact
`A2FP` key to unused DOC addresses `$E2-$E5`, followed by command `$01` at
`$E6`, before `$C03C` bit 4 and wavetable bit 6 can select bank 1. The same key
with command `$00` relocks. A bank-1 waveform write is still required before
playback-bank selection becomes active.

## Consequences

- Unmodified IIgs software always receives 64K-compatible behavior.
- Existing 128K-aware software must add a short unlock and relock sequence.
- Antoine Vignau's `$60/$70` upload and `$3F/$7F` playback conventions remain
  unchanged after unlock.
- Reset is always a reliable recovery path.
- Future incompatible protocol changes require a new key or command version,
  not reinterpretation of another native reserved bit.

