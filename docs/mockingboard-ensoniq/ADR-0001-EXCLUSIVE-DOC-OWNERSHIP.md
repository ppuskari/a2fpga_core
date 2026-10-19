# ADR 0001: Exclusive GS / Mockingboard DOC5503 ownership

- Date: 2026-10-19
- Status: Accepted for the first experimental sound personality
- Scope: Tang Nano 20K A2N20v2-Enhanced, branch `petar/mockingboard-ensoniq-p0`
- Decision: One physical/FPGA Ensoniq DOC5503 instance, controlled by exactly **one** software-facing personality at a time.

## Why this replaces the earlier design

The initial design assumed an independent six-voice sampled renderer could run in parallel with the native GS DOC. We do not require simultaneous GS DOC music and Mockingboard emulation. Exclusive ownership makes it possible to reuse the **existing, validated** DOC5503, its SDRAM waveform-fetch interface and HDMI output. No duplicate DOC-like renderer, waveform-fetch path or PCM mixer is needed.

## Modes

| Mode | AY/Mockingboard slot | GS Sound GLU host write access | DOC host register writer | Waveform RAM use | Audio |
|---|---|---|---|---|---|
| GS (default) | Disabled for this personality | Normal (unchanged) | Existing GLU | Existing 64/128K protocol | Existing DOC stereo audio |
| MB-DOC | Enabled, initially slot 4 | Blocked from *mutating* the DOC or its sample bank | AY-to-DOC translator | Preloaded MB patch/sample data | Same DOC stereo audio |

Do not interpret disabled GS sound ownership as disabling the IIgs CPU, GS/OS, video, or the rest of the FPGA peripheral features. GS software can run a Mockingboard-aware application with MB-DOC selected; native GS sound programs and Tool225 will not be active in that mode.

**Hard requirement:** The existing `sound_glu.ENABLE` gates DOC sound-memory reads as well as CPU register access. Setting `ENABLE=0` is **not** a correct way to relinquish GLU host ownership while keeping DOC playback functional. Split out GS CPU control write/read authorization from DOC execution and sample fetching. Preserve `ENABLE=1` for the engine when MB-DOC is selected.

## Static-mode P1 design

Use a single top-level parameter, conceptually:

```systemverilog
parameter bit AUDIO_MODE_MB_DOC = 1'b0;
```

This is a design contract, **not yet existing HDL**. At first, use a different bitstream for each mode. GS=0 is exactly the golden path; MB=1 is experimental and will be silent until translation, sample loading, and oscillator initialization are complete. No runtime switching until reset sequencing exists.

In GS mode, `Mockingboard.ENABLE` must not expose a competing DOC personality. In MB mode, the existing dual VIA/AY bus interface must remain software-visible, including interrupts and YM2149 readback, but its legacy `mb_audio_l/r` synthesis outputs must not be mixed. Use the AY register commands as control inputs for a new bridge.

## Shared DOC command boundary

Observed current `sound_glu.sv` implementation:

```
doc5503 (
    .clk_i(a2bus_if.clk_logic),
    .reset_n_i(a2bus_if.system_reset_n),
    .clk_en_i(a2bus_if.clk_7M_posedge),
    .cs_n_i(~doc_wr_r),
    .we_n_i(1'b0),
    .addr_i(doc_addr_r),
    .data_i(a2bus_if.data),
    ...
);
```

Insert the mode-dependent host-register multiplexer just ahead of `doc5503`:

- GS mode: original `doc_wr_r`, `doc_addr_r`, CPU data and existing GLU waveform-RAM path.
- MB-DOC mode: bridge-issued, synchronous `doc_write`, `doc_addr`, `doc_data`, plus bridge-controlled sample upload/initialization.
- Both remain in the current 54 MHz logic clock domain; DOC oscillator timing remains driven by the existing 7 MHz enable.
- Do not share one asynchronous `doc_data` bus without latching transaction-specific address/data. Existing GLU passes live `a2bus_if.data`; verify host capture timing when adding mux.
- Ensure no clock cycle can present two owners; no implicit mixing of register writes or wave-memory traffic.
- Preserve the DOC waveform fetch from the existing `DOC_MEM_PORT` and output `sg_audio_l/r` -> HDMI audio processing.

DOC register access and waveform memory upload are *separate* data paths. The AY bridge requires both: oscillator-register commands and some explicit patch-loader into the existing DOC sound RAM. The bridge cannot produce music merely by writing a DOC frequency register if RAM contains no valid waveform.

## MB-DOC voice policies

- The two Vias and AY/YM2149 register interfaces remain compatible with existing Mockingboard programs.
- Interpret three channels per chip, stereo left/right, with AY tone period (12-bit), noise period, mixer mask, fixed volume or envelope, and AY register-13 retrigger.
- Expose six *logical* channels. The translator may choose more than six of the 32 **physical** DOC oscillators for layering, noise, or envelopes, because the DOC belongs exclusively to MB-DOC mode.
- Ensoniq does not natively implement AY's shared noise generator or 16 envelope shapes: model those explicitly; validate before assuming hardware DOC sample-loop features are equivalent.
- A generic AY program supplies no instrument identity; choose explicit, configurable waveform/sample patches. Fidelity to original Mockingboard notes and timing is testable; enhanced tone color is an artistic mapping.
- Reuse the existing DOC 64/128K RAM layout for patches, maintaining bank logic and oscillator-fetch correctness. No additional concurrent streaming client is needed.
- Start with simple fixed waveforms and six voices. Layered/realistic samples and envelope enhancements come after verified bridge functionality.

## Transition/reset rules

Initial selection is **compile-time only**. Switching personality without reset is prohibited.

For any later selectable on-device mode: stop oscillator scheduling, mute/zero output, reset DOC and both controllers, initialize the destination sound RAM and patch table, reset volume/channel state and pending IRQ, then re-enable output. Select a mode only at startup or after a full controlled reset. The normal GS path must remain golden-compatible and the experimental MB mode must never send an uninitialized DOC waveform fetch.

## P1 implementation order

1. Add static `AUDIO_MODE_MB_DOC` selection, default 0, without changing golden behavior.
2. Independently test slot 4 VIA/AY register/IRQ behavior in MB mode; avoid changing native GS data paths.
3. Extract a bus-accurate AY event interface from VIA-driven BDIR/BC/DI; register-13 writes are events, including repeated identical values.
4. Add the DOC host-write selector and test that GS CPU writes cannot mutate DOC in MB mode while DOC itself still runs.
5. Implement a bounded waveform RAM preloader, verified before oscillator enable.
6. Map six logical voices into DOC registers and stereo assignments; test individual tones before envelopes/noise.
7. Run Gowin synth/PnR and real-IIgs tests for both bitstreams. Revert easily to the unchanged golden firmware.

## Rejection criteria

- Do **not** build a second Ensoniq/DOC-like renderer for the initial implementation.
- Do **not** use `ENABLE=0` on `sound_glu` as a substitute for gating GS host access.
- Do **not** sum YM2149 PCM into `core_audio_l_w/r_w` in enhanced mode.
- Do **not** modify the golden branch, native waveform protocol or golden bitstream.
- Do **not** claim MB-DOC is functional until sample RAM initialization, register bridging, and on-hardware audio tests pass.
