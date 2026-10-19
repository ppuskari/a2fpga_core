# P2A six-voice audible bridge — engineering checkpoint

Branch: `petar/mockingboard-ensoniq-p0`
Status: **HDL and simulation benches committed; NOT Gowin-synthesized, simulated or hardware-audited yet. Do not flash as a validated release.**

## What is implemented

`boards/a2n20v2-Enhanced/hdl/mb_doc_bridge.sv` owns the existing DOC5503 whenever `AUDIO_MODE_MB_DOC=1` or `MB_DOC_EXPERIMENT` is defined. It is not instantiated in normal GS mode.

At power-on / Apple II reset the bridge waits for the SDRAM controller's `sdram_init_complete`, then writes **64 consecutive 32-bit words** into the existing GLU sound-RAM port. Each word contains four consecutive entries of an offset-binary, repeating **256-byte triangle wave**, all in the range `$01..$FF`. Never use `$00` for an ordinary sample: in this DOC it halts the oscillator.

Once waveform preload finishes, it writes `$0E` to DOC register `$E1` to enable a scan of eight oscillator slots. Six slots play AY-style notes; slots 6 and 7 remain halted. This scan setting is part of the pitch conversion and must not be changed without recalculating FC.

The bridge captures two independent AY register streams, including 3 tone periods and 3 volumes per chip. The YM2149 and VIA cores still implement software-visible Mockingboard behavior and IRQs. The bridge uses **one shared 17-cycle restoring integer divider** to derive each oscillator's 16-bit frequency:

```
DOC_frequency_control = min(65535, floor(93623 / max(1, AY_period)))
```

This approximates Apple II AY tone at ~1.022727 MHz with eight DOC slots at ~7.159090 MHz DOC clock, 256-byte wave, and DOC resolution/table-size `$00` (WTS=0, RES=0). AY period zero uses period 1 and saturates. Pitch mapping is not exact at the extremes, especially period 1 (the DOC FC max limit) and very large tone periods (integer quantization).

Oscillator mapping:

| AY logical voice | DOC oscillator | Stereo channel | DOC control (RUN) |
|---|---:|---|---|
| Left A | 0 | Left | $10 |
| Left B | 1 | Left | $10 |
| Left C | 2 | Left | $10 |
| Right A | 3 | Right | $00 |
| Right B | 4 | Right | $00 |
| Right C | 5 | Right | $00 |

The **DOC code's current stereo convention** sends control channel bit 0 set to LEFT, unset to RIGHT. Initial oscillator setup emits `HALT`, WTP=0, RTS=0, FC-low, FC-high, amplitude, and RUN/HALT. Subsequent scans update FC low/high, amplitude, and RUN/HALT **without issuing a preliminary HALT**, retaining waveform phase while a note remains active.

The AY volume DAC uses a simple nonlinear 16-level lookup, peaking at 208/255 to avoid six-voice HDMI clipping. This is approximate, not a strict analog YM2149 volume model.

## Deliberately not implemented yet

- AY noise generator and tone/noise mixer conjunction: tone-enable bits are honored, but noise-only channels are silent.
- AY programmable envelopes: volume register bit 4 currently maps to a **fixed full-level preview**; correct AY envelope shape/period and reg-13 retriggering need a future HDL stage.
- AY I/O port behavior beyond existing YM2149 core, exact BDIR-held PA write detection beyond the P1 event capture.
- Instrument patch selection, layered oscillators, and realistic sampled instruments. This is a mono-type wavetable patch repeated independently on six stereo-assigned oscillators.
- Any claim that native GS and MB-DOC can play simultaneously (they cannot by design).

## Sound RAM / DOC ownership

In MB mode the bridge owns both (1) the host control write mux in `hdl/sound/sound_glu.sv` and (2) the GLU sound-memory write port, which now selects the bridge's word address/data/byte enables. The DOC sample-fetch port is unchanged. Native GS host accesses at $C03C-$C03F are gated from mutating the DOC in MB mode. In GS mode the multiplexer resolves to the original live CPU data path and original waveform-memory write signals.

The bridge waits for `glu_mem_if.ready` before moving to each next 32-bit SDRAM write. It drops the request for a full logic clock between writes to satisfy `sdram.sv`'s rising-edge request detector. There is no concurrent bank ownership.

## Tests

Run with Icarus Verilog from repository root:

```sh
sh tests/mb_doc/run_capture_test.sh
```

This invokes two benches:

1. `tb_mb_ay_capture.sv`: independent AY read/write control capture, repeated envelope register write events, invalid register addressing and reset.
2. `tb_mb_doc_bridge.sv`: 64 acknowledged waveform writes (256 checked nonzero bytes); 43 DOC register commands for first six voices; E1 oscillator count; pitch divisor outputs for six distinct AY periods; 3-left/3-right routing; continued oscillator phase; mute and zero-period saturation.

A GitHub Actions workflow is present at `.github/workflows/mb-ay-capture.yml`. **No completed CI run has been verified at time of this checkpoint.** Structural token balance checks were performed, but they are not a substitute for compilation/simulation.

## Hardware test priorities

1. Compile normal GS mode first; check no extra DOC/memory behavior, GS/OS/Tool225 playback and full DOC 128K status.
2. Compile MB mode by setting the top-level parameter `AUDIO_MODE_MB_DOC=1` or defining `MB_DOC_EXPERIMENT` in the Gowin project. Keep the golden .fs intact.
3. Confirm 64 RAM writes complete before any DOC RUN command; if it remains silent, inspect the RAM ready handshake, DOC E1 state, $A0-$A5 HALT state, and DOC waveform-fetch timeout debug bytes.
4. Test one AY tone on the left, then one on the right, then all six. Use register traces and known notes before full Mockingboard games.
5. Verify no repeated phase restart in subsequent scans; target a clean stable pitch.
6. Check FPGA resource/timing changes from the original 35% logic, 68% BSRAM, 58% DSP baseline.
7. Never treat this source-only commit as a tested .fs or silently replace the known-good golden bitstream.

## Following increments

P2B: hardware-confirm six sine/triangle-like sustained notes and proper AY address capture. P3: implement AY noise and envelope shapes, then multiple selectable timbres. **Only afterward** consider doubling or layering DOC oscillators for depth.
