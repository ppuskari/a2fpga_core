# DOC waveform-read diagnostics

## Purpose

This diagnostic checkpoint investigates missing, incorrect, or distorted
Ensoniq instruments during dense Music Studio 2.0 playback. It measures the
association between each DOC oscillator request and the waveform byte returned
by SDRAM.

The checkpoint is observational only. It does not change:

- DOC waveform addresses or bank selection
- SDRAM requests, arbitration, or returned data
- oscillator scheduling, modes, halt behavior, or accumulators
- mono/stereo routing
- `TOP_BIT_OFFSET`
- Sound GLU or HDMI gain
- mixer arithmetic or saturation
- the four existing one-second clipping histories

## Displayed counters

Each field is a hexadecimal, saturating event count for the last completed
125 ms interval. The visible value is held steady for the next interval.

| Overlay location | Counter | Meaning |
| --- | --- | --- |
| Top row, former final `$00` | `RQ` | A new DOC waveform request arrived while an earlier read was still outstanding. |
| Bottom row, former first saturated oscillator-3 counter | `TO` | A DOC oscillator slot expired before its waveform byte became usable, causing `$80` silence substitution. |
| Bottom row, former second saturated oscillator-3 counter | `LR` | SDRAM returned data after request ownership was absent or had become ambiguous. |

All three fields use this scale:

- `$00`: no events in the interval
- `$01`-`$FE`: exact event count
- `$FF`: 255 or more events

## Ownership rules

The diagnostic tracker is independent of the functional data path:

1. The first waveform request establishes a unique outstanding owner.
2. A second request before completion increments `RQ` and marks ownership
   ambiguous.
3. A normal uniquely owned response closes the outstanding interval.
4. A DOC slot timeout increments `TO` and invalidates the owner.
5. A response with no unique owner increments `LR`.
6. A response completing on the same clock as a new request closes the old
   interval and gives the new request clean ownership; it is not counted as an
   overlap.

The tracker observes the raw memory-completion event. This avoids falsely
counting a safe new request during the one-clock register delay between SDRAM
completion and `wave_data_ready_r` delivery to the DOC core.

## Reading the result

| `RQ` | `TO` | `LR` | Interpretation |
| --- | --- | --- | --- |
| `00` | `00` | `00` | No measured waveform-read failure in that interval. |
| nonzero | `00` | nonzero | Requests overlap and returned data has ambiguous ownership; address/byte-lane association is the leading fault. |
| nonzero | nonzero | any | SDRAM service is not consistently completing inside the DOC oscillator slot. |
| `00` | nonzero | nonzero | Responses are completing after the DOC deadline without a preceding request overlap. |
| `00` | nonzero | `00` | The DOC deadline expires, but no later response is observed in the same reporting pattern. |
| `00` | `00` | nonzero | A response appeared without a uniquely tracked request; investigate reset or response-pulse behavior. |

For the Music Studio 2.0 failure, record all three bytes while the native DOC
plays correctly and HDMI produces silence, wrong instruments, or distortion.
The existing oscillator-HALT fields and clip histories remain visible at the
same time.

## Modified files

- `hdl/sound/doc5503.sv`
- `hdl/sound/sound_glu.sv`
- `boards/a2n20v2-Enhanced/hdl/top.sv`

`hdl/debug/debugoverlay.sv` is unchanged from the live clipping-history
checkpoint.

## Build requirement

Rebuild `boards/a2n20v2-Enhanced/a2n20v2_enhanced.gprj` with the supported Gowin
toolchain before flashing. Any `.fs` already present under `impl/pnr` predates
this diagnostic source change.
