# Mockingboard-driven Ensoniq DOC5503 for A2N20v2-Enhanced

Status: **P1 structural HDL committed, NOT yet simulated/synthesized or hardware-tested**. P2 DOC sequencer and P3 waveform loader/audio are pending. Exclusive-mode design (2026-10-19).

## Objective

Use the **existing single** FPGA Ensoniq DOC5503 as either:

1. **Native GS (default)**: The original Apple IIgs Sound GLU at $C03C-$C03F controls the DOC, preserving 32-oscillator operation, the native 64/128K sound RAM extension, Tool225 streaming, and the validated stereo HDMI audio chain.
2. **Mockingboard → DOC (experiment)**: Unmodified Apple II Mockingboard software communicates with its dual 6522 VIA and AY/YM2149 control registers, and an AY-to-DOC bridge makes the **same DOC5503** play sampled/wavetable instruments.

There is no concurrent native GS and Mockingboard DOC activity, no second sampled-sound synthesizer and no YM2149 PCM audible in the enhanced mode. A GS computer can of course still execute Mockingboard-aware applications in the MB-DOC personality.

The initial selection will be compile-time via separate bitstreams, not an untested live switch. The native GS personality is default, with behavior maintained as in the golden build.

**Accepted architecture / implementation contract:** [ADR-0001-EXCLUSIVE-DOC-OWNERSHIP.md](ADR-0001-EXCLUSIVE-DOC-OWNERSHIP.md).

## Release ancestry and preservation

- Public upstream: `a2fpga/a2fpga_core`
- User's fork: `ppuskari/a2fpga_core`
- Golden branch: `petar/doc128k-p0x-golden`
- Golden release tag: `a2n20v2-enhanced-doc128k-p0x-golden-20260816`
- Parent SHA: `eb6d2726fd252a54fe84739cb767361adf11d657`
- Golden FPGA SHA256: `7C011DCCFD3955478307C568AA70BEBF305FAC11770B1289229B1FF593AA9169`
- Experimental branch: `petar/mockingboard-ensoniq-p0`

**Do not edit the golden branch.** Every experimental .fs must be distinguishable and reversible.

## Verified source facts

- `hdl/mockingboard/mockingboard.sv`: dual 6522 VIA, dual YM2149, IRQ and stereo 10-bit legacy PSG outputs.
- `hdl/slots/slots.hex`: `00 00 03 05 02 04 06 01`; card ID 2 occupies slot 4 in the checked source. Confirm actual BL616/slotmaker configuration on hardware.
- `boards/a2n20v2-Enhanced/hdl/top.sv`: `MOCKINGBOARD_ENABLE = 0`, `ENSONIQ_ENABLE = 1`. `core_audio_l_w/r_w` currently pass only `sg_audio_l/r`.
- `hdl/sound/sound_glu.sv`: one `doc5503` instance. Native GLU host writes currently feed `doc_wr_r`, `doc_addr_r` and live `a2bus_if.data`. FPGA DOC oscillator timing still uses the existing 7 MHz enable.
- **Do not just set `sound_glu.ENABLE=0` in MB mode:** that flag is also used to gate sound-memory fetches, and would disable DOC output. Instead gate native GS *host* control while retaining the engine's memory/clock/data path.
- `hdl/support/YM2149.sv`: PSG register writes sample BDIR/BC/DI each rising logic clock; CE controls synthesis timing, not the register-write sampling.

## Proposed logical path

```text
           Static exclusive mode (GS default / MB-DOC experimental)
                |                              |
 GS Sound GLU $C03C-$C03F               Mockingboard slot 4
                |                       2x VIA + 2x AY
                |                              |
                |                     AY register-write trace
                |                              |
                |                     AY tone/envelope/noise
                |                        -> DOC commands
                |                              |
                +---------- exclusive host ----+
                              mux
                               |
                       Single DOC5503
                          32 oscillators
                               ^
                               |
                 Mode-owned sample RAM preload
                               |
                    Existing SDRAM sound RAM
                               |
                       Existing DOC mixer
                               |
                 Existing 44.1 kHz HDMI audio
```

On Mockingboard commands, preserve all software-visible VIA/AY behavior and IRQs. Six logical AY voices (3L + 3R) can be implemented using **six or more** native DOC oscillators; this mode owns all 32, enabling later layering and sampled timbres. AY tone/noise gates, shared noise source and envelope behavior require explicit semantic translation, not just swapping sound samples.

MB-DOC requires a deterministic waveform/patch **preload** into the same existing DOC sound RAM before enabling voices. Source and timing of this upload (FPGA loader or BL616-assisted upload) must be validated; register writes alone cannot produce useful audio from uninitialized memory.

## Stages

- **P0: Architecture (done).** Preserve the gold release, establish this experimental branch and settle mutually exclusive single-DOC ownership.
- **P1: Compatibility / mode skeleton (HDL committed; verification pending).** Add build-time GS/MB mode selector defaulting to GS, bring up slot 4 dual VIA/AY, capture AY write events, ensure GS host cannot write to the DOC in MB mode **without disabling DOC memory reads**. Verify simulation and resource/timing costs.
- **P2: DOC control bridge.** Design and test a serialized host-register writer with correct address/data capture and ACK cadence. Translate six logical AY tone/volume/mixer/envelope voices to DOC channel and register updates.
- **P3: Waveform initialization and audible MB-DOC.** Load a small verified sample bank into DOC sound RAM; enable the DOC oscillators after load; test tones and left/right stereo, then noise/envelopes and optional patches.
- **P4: Hardware and golden regression.** Synthesize/PnR, test MB recognition/IRQ/audio and all native GS audio/128K Tool225 behavior in the *GS personality*, keep separate build artifacts and measured stats.
- **P5: Enhanced instrument patches and startup mode selection.** More sophisticated samples, optional layers, and later a safe reset-controlled configuration selection; no unsupported hot switching.

See [P1-CHECKLIST.md](P1-CHECKLIST.md), [P1-IMPLEMENTATION.md](P1-IMPLEMENTATION.md) and [RESOURCE-BASELINE.md](RESOURCE-BASELINE.md). The committed [AY capture test](../../tests/mb_doc/tb_mb_ay_capture.sv) and [CI workflow](../../.github/workflows/mb-ay-capture.yml) require execution; no passing result has yet been verified.

## Initial acceptance

- GS-mode .fs remains behaviorally consistent with golden native Ensoniq/Tool225 streaming.
- MB-DOC software sees a real dual-VIA Mockingboard in the configured slot and all IRQ/timer and register read/write behaviors survive.
- MB-DOC drives **the real existing DOC5503** using sampled waveforms and provides stereo via the current HDMI pipeline. The original YM2149 PCM is not audible.
- The GS sound register path cannot alter DOC registers/sample bank while MB-DOC owns them.
- No new clock PLL and no second large renderer; document BSRAM/DSP and timing after synthesis.
- No simultaneous GS/MB DOC control, no uninitialized samples and no silent switching without a full reset.
