# M6.6b — Native YM FX per-channel compatibility, independent merge candidate

**Date:** 2026-11-16
**Branch:** `petar/mb-doc-m66b-channel-ay-parity-20261116`
**Parent:** `petar/mb-doc-m66a-dual-bank-fx-20261116`
**Golden source:** `petar/mb-doc-m641-coherent-20261113` and verified direct Vizio optical recording `641good.wav`
**Status:** GitHub Actions Icarus regressions pass. **Gowin synthesis/PnR and hardware A–O listening NOT YET PERFORMED.**

## Why this correction is needed

The M6.6a experimental sample classifier cannot identify "gunshot," "ocean," "train," etc. from a single AY noise register. It replays one-shots when the original AY program continuously clocks/modulates noise and tone. Its one-pending-event-per-chip policy is lossy. On hardware the demo disk A–G effects were wrong; H–K partial; L bomb missed its explosion; M partially sounded; N–O had repeated unrelated FX.

M6.6b is deliberately a **compatibility/reference** pass: for the channels carrying programmable noise or recognized FX patterns, use the original on-FPGA live YM2149 output itself. Do NOT claim the sampled Ensoniq engine is already emulating that sound accurately. It is a safe way to isolate AY semantics and rebuild enhanced samples later.

## Implemented

- Add `mb_doc_ay_fx_router.sv` generating a **three-bit channel mask for each original AY chip**. A channel uses live native YM if its active-low R7 noise gate is enabled and its volume/envelope is active, if it participates in the previously validated two-channel title sweep, or if all three channels make the known triple-envelope effect. A normal tone-only piano channel is untouched.
- The existing `Mockingboard.sv` YM2149 A/B/C output wires are summed into a **new secondary FX-only stereo path** under those masks. The original full AY stereo `audio_l_o/audio_r_o`, VIAs, SSC/SSI263 speech, clocks, registers and interrupts are unchanged.
- The DOC bridge prevents a masked channel from also producing sampled piano. It retains the M6.4.1 coherent publication and de-click volume release, avoiding the old whole-chip AY bypass that turned chords into chip music.
- The 54 MHz audio path high-pass filters selected AY PCM as before, compensates native gain for simultaneous DOC, adds it **alongside** DOC piano and speech using widened, saturating stereo arithmetic, then keeps the same HDMI packetizer and final limiter.
- The M6.5b sampled one-shot FX commands are DISABLED while native compatibility is enabled. The **existing dual 64KiB Bank0/Bank1 preload and RTS bank selection circuits remain intact** for later sample enhancements. The DOC oscillator budget and sample banks are unchanged; the ghost/incorrect effects from lossy one-shot classification no longer play on top of native noise.
- No diagnostic pilot, no video overlay, no BL616 or MCU mode-selector work, no new ProDOS software interfaces and no SenseiPlay edits. The other workstream can merge independently.

## Top-level parameters (Enhanced)

```systemverilog
parameter bit MB_DOC_FX_AY_BYPASS_ENABLE = 1'b0, // original whole-chip bypass OFF
parameter bit MB_DOC_DECLICK_ENABLE = 1'b1,
parameter bit MB_DOC_COHERENT_PUBLISH_ENABLE = 1'b1,
parameter bit MB_DOC_SAMPLED_FX_ENABLE = 1'b1, // preload preserved
parameter bit MB_DOC_DUAL_BANK_FX_ENABLE = 1'b1,
parameter bit MB_DOC_AY_FX_CHANNEL_COMPAT_ENABLE = 1'b1,
parameter bit MB_DOC_AY_FX_FORCE_NATIVE_ALL = 1'b0,
```

Two useful A/B compilation modes in **the same branch**, change just one top parameter:
- **M6.6b-Hybrid (default)** `MB_DOC_AY_FX_FORCE_NATIVE_ALL = 1'b0`: routed noise/triple-envelope/recognized title-sweep FX through YM channels, other channels play DOC sampled piano.
- **M6.6b-AY Reference** `MB_DOC_AY_FX_FORCE_NATIVE_ALL = 1'b1`: turn all six AY channels into native YM, mute six DOC piano voices. The comparison is for **effects A–O ONLY**, not final music playback. Same RAM preload, sample engine, HDMI and MCU. This is an exact source-waveform reference at the channel-output boundary, not a guarantee that downstream gain/capture matches external analog Mockingboard hardware.

The original native AY full-chip audio path is still available in standard Mockingboard mode. In MB-DOC this is now a sidecar, NOT a whole-chip replacement.

## Software regressions

GitHub Actions: `.github/workflows/mb-doc-m66b-channel-parity.yml` must pass. It executes:
- Original dual-AY/VIA register capture and six-piano-voice M6 control tests.
- M6.4 de-click and M6.4.1 coherent publication (RES variants).
- M6.5a event protocol and M6.5b sampled one-shots with compatibility OFF.
- M6.6a 128KiB dual-bank preload and per-oscillator bank select with compatibility OFF.
- New M6.6b static decoder: tone-only music, noise-bearing tone+noise, envelope at zero-phase, independent left and right, triple envelope and title-sweep hold.
- New M6.6b end-to-end DOC bridge: piano A to YM noise to piano A, correct DOC piano release, stereo independence, no sampled one-shot commands while parity mode is enabled.

These are deterministic, synthetic AY control patterns. **The demo disk's A–O actual register trace or analog output is NOT embedded in CI**; the upcoming hardware A–O playback is the acceptance test.

## Checkout — PowerShell 5.1, one line each

```powershell
git clone --single-branch --branch petar/mb-doc-m66b-channel-ay-parity-20261116 https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-m66b
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-m66b
```

```powershell
py -3 tools\extract_synthlab_piano.py --download
```

Open Gowin project `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj`. Build/place-route from this checkout; verify 54MHz logic, 27MHz pixel and HDMI interface paths against full PnR reports. Preserve M6.4.1 and M6.6a original `.fs` bitstreams and `641good.wav`. **FPGA ONLY**; no BL616 flash, MCU selector or ProDOS NTP changes.

Use direct Tang Nano HDMI -> Vizio LCD, Vizio optical out -> Mac Pro capture. Keep faulty HDMI splitter/extractor out of signal path.

## Hardware test plan

1. In default hybrid mode, verify **Sugar Plum Fairy, Minute Waltz, Pop Goes the Weasel** against `641good.wav`: piano pitches, no lost notes, de-click, repeat timing and HDMI/video stability.
2. Test **A gunshot, B machine gun, C train, D helicopter, E explosion, F ocean, G swish**: these require properly evolving noise and may now improve with the original live YM channels instead of one-shot samples.
3. Test **H pump, I clock, J power generator, K laser, L bomb, M multiple tones, N/O multiple noise**. On L the descending sweep and explosion tail must BOTH be present.
4. Record a 44.1kHz stereo WAV including 2–3 repeats of each test. Note exact A–O labels and any misrouted channel, dropout, missing envelope, piano ghost, excessive loudness or static.
5. If any tone-only effects are still piano-like or wrong, **switch only** `MB_DOC_AY_FX_FORCE_NATIVE_ALL` from `1'b0` to `1'b1`, synthesize/PnR a second bitstream and play A–O again. This establishes what the existing native YM model actually produces; it will intentionally make the classical demo songs sound like chip music. Do not use it as golden music mode.
6. If all-native produces the correct effects but hybrid fails, tune per-channel FX classification and develop live tone sweep detection; if even all-native fails, investigate the YM core/AY register capture, downstream gain/filter and original demo behavior. Do not attribute it to absent 128KiB audio samples.
7. Restore M6.4.1 bitstream if note integrity or HDMI becomes unstable.

## Known limits and next milestone

This is not an Ensoniq-only emulation of the AY. The native YM core is the fidelity reference for sound effects. The hybrid masks include noise-bearing channels, known dual-A/B title glide and triple-envelope; they do **not yet identify every other tone-only sweep or exotic sound-program pattern**, so individual A–O misses are expected. Generic score-to-instrument mapping is impossible without explicit metadata/profile. Extra 128KiB RAM does not grant extra DOC oscillators.

Next M6.6c after A–O recordings: capture exact AY R0–R13 time-series for each effect, identify continuous glide/envelope/mixer patterns per channel, and replace native YM sounds with frequency-modulated DOC samples only where they meet an explicit audio parity acceptance test. Add a small event history/FIFO instead of one-shot guesses. Keep the separate MCU startup/Native DOC/Shared/SenseiPlay merge interface independent.
