# ADR 0002: Progressive Mockingboard sound backends

- Date: 2026-10-19
- Status: **Accepted as project direction; future stages are not implemented**
- Applies to: `petar/mockingboard-ensoniq-p0`
- Prior decision: [ADR 0001 — exclusive GS/Mockingboard DOC ownership](ADR-0001-EXCLUSIVE-DOC-OWNERSHIP.md)

## Goal

Run existing, **unmodified Apple II Mockingboard programs** with increasingly capable instrument sounds, while preserving compatibility with the original dual-6522/AY bus protocol and the golden IIgs Ensoniq mode.

Progressive backends:

1. **Six voices on the existing Ensoniq DOC5503** with a minimal sample bank and accurate AY pitch, volume and stereo routing.
2. **Faithful AY behaviors and improved DOC patches**, including envelope/noise, separate instrument patches and optionally layered DOC oscillators *after* the six-voice baseline passes.
3. **SoundFont-to-DOC conversion**: convert a subset of SF2 instrument sample data *offline* into a constrained DOC patch bank that plays entirely in the existing FPGA engine.
4. **FluidSynth backend**: export interpreted musical events from the FPGA through a transport to a capable external processor running FluidSynth and an SF2/SF3 SoundFont; optional future PCM audio return to A2FPGA HDMI.
5. **Selectable sound personalities/profiles** based on startup configuration, retaining native GS mode as a separate exclusive DOC ownership choice.

This sequence is intentional. **Do not** block a working six-channel baseline on SoundFonts, MIDI or external CPU code. **Do not** introduce duplicated oscillators until timing, compatibility and clipping have been measured with six.

## Architecture boundary to preserve

```text
Apple II CPU / slot-4 Mockingboard software (unchanged)
                      |
               2 x 6522 VIA
                      |
               2 x AY bus protocol
                      |
       AY register event + snapshot decoder
                      |
     AY semantics (pitch/noise/mixer/envelope,
        6 logical channels, timing and reset)
                      |
          backend-neutral voice events
         /                         \
  Local DOC backend          External event stream
  existing oscillator        serial/SPI/USB/network
  host command engine                 |
         |                        FluidSynth
  DOC PCM/waveform RAM         SF2/SF3 instruments
         |                         audio
   A2FPGA HDMI out                 initially on
                              companion device
```

The present `mb_doc_bridge.sv` combines register shadows, six-channel translation, patch preload and DOC writes in one module. This is appropriate for the first validation build. When real hardware confirms it, refactor in **small parity-tested commits** to introduce backend-neutral events; do not replace all working logic at once.

Suggested normalized event contract, to refine through software traces:

- `voice_id`: 0..5; channels 0..2 left, 3..5 right
- `pitch`: retain *original 12-bit AY tone period* (and timebase), not only rounded MIDI note; continuous retuning/glissando must survive
- `amplitude`: fixed 4-bit AY level or envelope-derived level, with correct shared envelope shape and register 13 retrigger events
- `tone_enable` and `noise_enable`: independent mixer states and shared AY noise generator properties
- `gate/trigger`: modeled from original behavior, explicitly distinct from a MIDI note-on: AY tone channels have no native note-on command
- `timestamp/order`: preserve ordering across chips and capture timer-driven updates; avoid arbitrary note durations or coalescing intentional retriggers
- `patch_id`: configurable profile metadata **not** encoded in unmodified AY register writes
- `reset` and `all_off` events

This is a proposed interface, not yet stable HDL.

## Backends and acceptance gates

### Stage A — existing six-voice DOC prototype: current top priority

Current source exists: `boards/a2n20v2-Enhanced/hdl/mb_doc_bridge.sv` and [P2A-SIX-VOICE.md](P2A-SIX-VOICE.md).

Gate:
- Simulation passes for the dual AY capture and DOC bridge.
- Gowin synthesis/PnR succeeds and measurements remain within timing/resource budgets.
- Genuine left A/B/C and right A/B/C notes sound independently and have stable pitch/volume; waveform preload and $00 sample-stop avoidance work.
- Golden GS/Tool225 regression passes in native mode.
- A simple game/driver can probe dual VIAs/AY readback and timer interrupts on hardware.

**Current status: source committed; these gates are not yet verified.**

### Stage B — faithful AY semantics, DOC effects and patch profiles

- Correct shared AY noise and tone/noise gating; correctly timed envelope generator and register-13 restart.
- Faithful fallback/profile to compare against the original YM reference path.
- Per-logical-voice instrument selection from configuration and optional per-game profiles.
- Dedicated patch layout in 64/128K DOC sound RAM, not competing with native GS software.
- Optional two-or-more-DOC-oscillator layering per one AY voice **only after** the six-voice renderer and clipping/headroom regressions pass.

Gate: real-game compatibility and timing, deterministic patch playback, bounded latency, measured gain/headroom.

### Stage C — offline SoundFont-to-DOC sample bank

- Write a host-side converter to extract selected SF2 samples and presets, choose note ranges, and resample/requantize into DOC-compatible 8-bit offset-binary waveform tables.
- Keep valid loop/window boundaries, nonzero PCM samples as needed to avoid accidental $00 halt, and documented table-size/resolution settings.
- Respect the existing DOC waveform RAM budget and bank-selection/64-vs-128K extension rules; place/reload patches safely before oscillator start.
- Provide stable patch bank metadata: instrument name, root frequency, pitch range, loop points and source licensing/provenance.
- Not all SF2 instruments/effects can be represented faithfully by the DOC. Unsupported modulators, filters, large multisamples, envelopes and effects must be reported as conversions/approximations.

Gate: several distinct instrument samples audible on native DOC, one sample bank reproducibly reloadable, no unexpected clipping/halts.

### Stage D — FluidSynth externally rendered SoundFont mode

- Derive MIDI-compatible note/control events from the original six AY voices, including precise pitch bends or a higher-resolution private protocol for continuous frequency changes.
- **AY does not carry MIDI note-on/off or instrument IDs**. Establish and test a note/gate inference policy for music games with rapid period and volume changes; distinguish repeated triggers from uninterrupted sustained tones.
- Carry voice identity, stereo assignment, per-voice volume, program selection, timing and reset to companion synthesizer.
- Run FluidSynth on an external processor capable of its workload, using SF2/SF3 banks. Treat BL616 as a possible event transport endpoint, **not** as a presumed suitable full FluidSynth host.
- First version plays PCM on companion audio hardware. Returning PCM to the FPGA for HDMI requires a separate resampled, buffered, clock-domain-safe transport, and must not be confused with DOC-generated audio.
- The external FluidSynth renderer may be selected as the MB audio backend; it does not simultaneously own the DOC. Native GS remains another startup-selected personality.

Gate: six simultaneous instruments, measured latency/jitter and correct stop/start behavior during game resets, unmodified software compatibility.

### Stage E — profile selection / user experience

- Safe startup-time selection of native GS, DOC classic/enhanced, DOC SoundFont bank or external FluidSynth backend.
- Bank/profile configuration and external-synth disconnect/fallback behavior.
- Avoid hot-swapping DOC ownership without the full reset/mute/init sequence in ADR 0001.
- Archive bitstreams, firmware versions, converter/tool versions and profile checksums for reproducibility.

## Immediate next step, not to be skipped

**Execute and debug the two existing Icarus benches, synthesize the Enhanced MB configuration, then test one note per side and all six together on real hardware.** No FluidSynth, SoundFont conversion, duplicated oscillators or new architecture refactor should supersede this gate.

## Design truths and non-goals

- This is instrument *reinterpretation*, not an automatic restoration of missing instrument metadata: ordinary AY writes do not identify violins, pianos or General MIDI patches.
- The DOC-only SoundFont stage renders locally using the validated oscillator engine. Full FluidSynth requires a separate software runtime and is **not** implemented inside the DOC or Gowin FPGA.
- All later ideas must preserve the user's original six-voice GS/Mockingboard exclusive-mode decision, untouched golden branch and original application compatibility.
