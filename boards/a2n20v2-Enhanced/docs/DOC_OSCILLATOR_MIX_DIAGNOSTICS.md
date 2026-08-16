# DOC oscillator-to-mixer diagnostics

This diagnostic checkpoint investigates Music Studio 2.0 playback that is
full and correct on the native IIgs DOC output but initially silent, then
sparse or incorrect, on the A2FPGA HDMI DOC output.

The preceding read-path build showed zero outstanding-read overlaps, zero
waveform-fetch timeouts, and zero late or ambiguously owned responses. This
checkpoint therefore observes the oscillator output and completed-mix path
without changing audio behavior.

## Bit-field rows

Each displayed bit is an activity result from the last completed 125 ms
interval. Oscillator 0 is at the far left and oscillator 31 is at the far
right.

| Row | Fields | Meaning |
| --- | --- | --- |
| Top | OSC 0-7, 8-15, 16-23, 24-31 | Oscillator produced a nonzero signed sample times volume result |
| Bottom | OSC 0-7, 8-15, 16-23, 24-31 | Oscillator executed `OSC_MIX` |

An odd oscillator in SYNC/AM mode intentionally controls the following
oscillator's volume and does not enter `OSC_MIX`. It can therefore be absent
from both rows without indicating a fault.

## Hexadecimal rows

The first hexadecimal row is unchanged:

| Byte | Meaning |
| --- | --- |
| 0-3 | Modes for oscillators 0-7 |
| 4 | DOC oscillator-enable register |
| 5 | Completed DOC mixer saturation flags |
| 6 | Sound GLU control/global volume |
| 7 | Outstanding DOC read overlap count |

The second hexadecimal row is:

| Byte | Meaning |
| --- | --- |
| 0 | DOC channel-address activity mask, channels 8-15 |
| 1 | DOC channel-address activity mask, channels 0-7 |
| 2 | Left completed-mix nonzero history |
| 3 | Right completed-mix nonzero history |
| 4 | Most recent host control-write oscillator |
| 5 | Most recent host control-write data |
| 6 | Waveform-fetch timeout count |
| 7 | Late or ambiguously owned response count |

The left and right history bytes cover one second. Bit 0 is the newest 125 ms
slice and bit 7 is the oldest. A set bit means at least one completed DOC mix
published a nonzero 16-bit value during that slice.

## How to interpret the Music Studio test

- Top bit set, bottom bit clear: a nonzero oscillator was suppressed before
  `OSC_MIX`.
- Top and bottom bits set, but its channel-address bit is clear: inconsistent
  mixer routing or diagnostic ownership.
- Bottom activity and channel activity are present while both left/right
  histories stay zero: contributions cancel or the completed mix is lost
  before publication.
- Only left or only right history advances: the failure is already present in
  the DOC completed stereo mix, before HDMI post-gain processing.
- Timeout or late-response count becomes nonzero: revisit the waveform-read
  path despite the preceding clean capture.

## Functional boundary

This build does not change oscillator control, HALT/SWAP/SYNC-AM behavior,
waveform addresses or data, accumulators, channel routing, mono/stereo
selection, `TOP_BIT_OFFSET`, the HDMI `45/32` gain, or saturation arithmetic.
The diagnostic logic only observes existing FSM states and mixer values.

