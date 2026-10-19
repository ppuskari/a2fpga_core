# Mockingboard-to-Ensoniq Wavetable Project

Status: P0 kickoff / architecture, **no gateware changes yet**.

## Purpose

Run unmodified Apple II Mockingboard software on an A2N20v2-Enhanced and render its music/sound effects with sample-based Ensoniq-style timbres rather than using the two original AY/YM2149 synthesized audio outputs. Maintain Mockingboard register behavior, slot selection, timer/IRQ timing, and stereo placement. Keep the existing native IIgs Ensoniq DOC5503 audio path intact.

This is an *instrument reinterpretation*: Mockingboard register writes specify AY tone/noise/volume/envelope controls, **not** instrument names or PCM sample IDs. Any enhanced timbres require an explicit, deterministic patch-mapping policy and can intentionally sound different from a physical Mockingboard.

## Immutable ancestry

- Upstream: `a2fpga/a2fpga_core`
- Existing fork: `ppuskari/a2fpga_core`
- Branch/tag: `petar/doc128k-p0x-golden`, `a2n20v2-enhanced-doc128k-p0x-golden-20260816`
- Exact parent commit: `eb6d2726fd252a54fe84739cb767361adf11d657`
- Golden bitstream SHA-256: `7C011DCCFD3955478307C568AA70BEBF305FAC11770B1289229B1FF593AA9169`
- This experiment: `petar/mockingboard-ensoniq-p0`; NEVER commit experimental HDL changes to the golden branch.

## Confirmed current wiring

- `hdl/mockingboard/mockingboard.sv` implements 2 x 6522 VIA, 2 x YM2149, two 10-bit channel sums, and IRQ.
- `boards/a2n20v2-Enhanced/hdl/top.sv` has `MOCKINGBOARD_ENABLE = 0` and `ENSONIQ_ENABLE = 1`.
- `hdl/slots/slots.hex` already assigns card ID 2 to slot 4: `00 00 03 05 02 04 06 01`.
- IRQ combination already includes `mb_irq_n`.
- The current `core_audio_l_w/r_w` assignments pass **only** `sg_audio_l/r`; the old AY summing lines are commented out. Merely enabling the Mockingboard does not make it audible.

## Intended datapath

```text
Apple II software (slot 4, normally $C400-$C4FF)
       |
2 x 6522 VIA -- preserve readback/timers/IRQ
       |
AY bus (BDIR/BC/address/data), 2 chips
       |
AY register-write monitor + 2 x 16 register shadow banks
       |
Six-voice translator: tone periods, enable masks, noise,
AY envelope shape/period, per-channel volume
       |
Sample-based waveform / patch renderer, stereo 3L + 3R
       |
Signed saturating mixer with native IIgs DOC GLU output
       |
Existing audio clock crossing -> audio_out -> HDMI gain
```

Preserve existing YM2149 cores as a selectable *reference* for behavioral A/B tests and readback while developing; do not route their generated PCM to the **enhanced** audio output. The actual YM2149.sv registers sample BDIR/BC/DI on every rising edge of CLK (not on CE; CE clocks the synthesis dividers). Derive logical register events from VIA port-write transitions or explicitly verify bus-phase behavior. Avoid false/repeated events while BDIR/BC remain asserted, but preserve intentionally repeated writes (especially AY register 13 envelope restart).

## Renderer decision

**First functional target:** isolated six-voice PCM wavetable renderer, modeled on DOC-style 8-bit waveforms and 16-bit stereo output, fed by AY shadow registers. Use a private, small ROM/sample bank and private phase accumulators, so Mockingboard playback cannot overwrite the native DOC's 64/128-KB sound RAM, commandeer native oscillator registers, or disturb Tool225 streaming. The output then shares the verified HDMI audio chain.

**Later integration candidate:** send translated events into the existing DOC5503 oscillator engine itself. This requires explicit register/voice ownership, arbitration, waveform-memory allocation and concurrent native IIgs audio behavior. It must not silently seize six of the 32 DOC oscillators or use the 128K extension bank, which would break native DOC programs and streaming. Decide after synthesis/timing-resource review and tests. An independent DOC-style renderer is the safer first milestone; it does not yet mean that the native DOC engine is driving those voices.

A sampled waveform is not automatically a richer sound: for a meaningful improvement provide switchable instrument samples and envelopes, with faithful AY reference mode to check software compatibility.

## Small, hardware-testable milestones

- **P0: Baseline (this commit).** Branch directly from August 16 golden release and capture design/acceptance criteria. No source or .fs modifications.
- **P1: Compatibility decode.** Add a build-time disabled-by-default Mockingboard bring-up option; validate slot 4 ID 2, VIA timer/IRQ behavior, AY address/data register reads and writes. Keep native Ensoniq HDMI audio unchanged.
- **P2: Software reference tests.** Record/replay AY register traces and compute the six interpreted voice states. Verify tone period zero behavior, envelope and noise semantics and L/R routing.
- **P3: Isolated sampled renderer.** Add a small FPGA sample bank, pitch conversion/phase accumulators, envelope/volume mapping, noise/percussion mapping, and signed saturating stereo summation. In enhanced mode, AY audio sums are not mixed.
- **P4: Real hardware verification.** Synth/PnR/bitstream on Tang Nano 20K. Confirm space/timing headroom, real Mockingboard software playback, stable slot and IRQ behavior, correct stereo and clipping, preserved existing IIgs DOC audio.
- **P5: Advanced patches and optional shared native DOC backend.** Only after proven concurrency rules and regression coverage.

Do one change per hardware-testable stage. Keep an exact known-good bitstream, compile reports, evidence, and a rollback commit for every candidate build.

## Acceptance / non-regressions

1. Apple II and Apple IIgs Mockingboard applications recognize slot 4, use VIA interrupts normally and require **no software modification**.
2. Six logical channels (3 left / 3 right) follow AY pitch, volume, mixer enables, envelopes and noise with deterministic, testable semantics.
3. Enhanced sound is generated from PCM/wavetable samples; YM2149 PCM output is not mixed in that mode.
4. Native DOC5503 register access, original Ensoniq sound and 128K waveform protocol work unmodified.
5. Existing DOC/Tool225 PCM playback regression, including the stable long-running streamer, remains clean; no competing waveform RAM writes.
6. Signed mixing saturates rather than wrapping; document loudness/HDMI gain and measured PnR utilization.
7. Stock golden branch and bitstream remain untouched.

Out of scope for initial milestones: Votrax voice support; automatic identification of a game's intended orchestral instruments; changes to BL616 firmware or GS/OS Tool225.
