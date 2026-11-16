# M6.5b experimental sampled FX OSC6/7 — handoff

**2026-11-16** — experimental branch: petar/mb-doc-m65b-procedural-fx-osc67-20261116
**Golden hardware:** petar/mb-doc-m641-coherent-20261113 (641good.wav).
**Status:** RTL simulated. Gowin timing and audible hardware behavior unverified.

## What's implemented

- New register-faithful dual AY event decoder identifies each AY's active-low R7 noise gates, tone/noise combinations, R8–10 envelope or fixed volume, R6 noise-frequency changes, and repeated R13 envelope restart writes.
- New 20KiB diagnostic bank, procedurally generated at boot into **existing external DOC sound SDRAM** with no extra 20KiB BSRAM array.
- Golden seven-zone piano memory occupies $0000..$15FF; new FX bank $2000..$6FFF, seven waveform slots, each with exactly one terminal DOC HALT byte.
- Patches: explosion $2000 (8KiB), kick $4000 (1KiB), snare $4400 (1KiB), tom $4800 (1KiB), hihat $4C00 (1KiB), laser $5000 (2KiB), cymbal $6000 (4KiB).
- Event renderer sends left FX on DOC oscillator 6 and right FX on oscillator 7. DOC0..DOC5 piano voice code and frequency are unchanged.
- Each FX trigger uses HALT, WTP, RTS, frequency L/H, volume, RUN. Noise period controls a rough uncalibrated playback rate.
- Whole-chip AY FX bypass, video overlay, HDMI pilot remain disabled. R11 SSI263, BL616 firmware, shared DOC core and HDMI limiter unchanged.

## Feature flags

Experimental Enhanced top defaults:

    MB_DOC_FX_AY_BYPASS_ENABLE = 1'b0
    MB_DOC_DECLICK_ENABLE = 1'b1
    MB_DOC_COHERENT_PUBLISH_ENABLE = 1'b1
    MB_DOC_FX_EVENT_CAPTURE_ENABLE = 1'b1
    MB_DOC_SAMPLED_FX_ENABLE = 1'b1

The standalone bridge parameters default the new FX functions OFF, preserving older regression behavior.

## Test evidence and deployment gate

CI workflow: .github/workflows/mb-doc-m65b-fx-playback.yml
Tests: M6, M6.4, M6.4.1, M6.5a, seven FX waveform terminal bytes, 6528 sequential SDRAM words (1408 original piano + 5120 FX), left/right oscillator 6/7 commands, and unchanged whole-chip AY mux.

A passing RTL simulation does NOT establish FPGA route timing, analog timbre, note-tail correctness or sustained noise parity.

## PowerShell 5.1 single-line checkout

    git clone --single-branch --branch petar/mb-doc-m65b-procedural-fx-osc67-20261116 https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-m65b

    Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-m65b

    py -3 tools\extract_synthlab_piano.py --download

Gowin project: boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj

Save the golden M6.4.1 FPGA bitstream and timing report. Run synthesis, place-and-route and check post-route STA for **this** experiment before any FPGA reprogramming. FPGA bitstream ONLY: do not reflash the BL616.

Use direct Tang Nano HDMI to Vizio. Record optical stereo through the Vizio rather than the faulty splitter/extractor. First verify SUGAR2, MINUTE and WEASEL note accuracy against 641good.wav; then test title explosions and effects and both OSC6/7 channels. Watch for retrigger clicks or missing notes, pitch, sound quality, boot delay and PnR overhead.

## Limitations: what remains to reach complete Mockingboard score compatibility

This first bank is **algorithmic demonstration PCM**, not production-quality acoustic explosions/percussion and not an exact AY noise emulator. The original AY does not encode instrument IDs. Current heuristics classify tone-plus-noise patterns into sample patches, with one pending event per chip (latest wins) and only two simultaneous FX oscillators. It does not guarantee lossless high-rate FX streams.

The remaining fidelity work must include: exact AY noise LFSR with clocked noise-period control, exact per-channel tone AND noise gating, 16 R13 shape live envelopes during FX (the native YM still computes them), actual sampled FX release/de-click and pitch calibration, queued simultaneous notes, track instrument profiles and user WAV streaming into SDRAM without eating the nearly full FPGA BSRAM budget. Provide both AY-faithful parity mode for unmodified software and optional enhanced sample patch mode.

The existing M6.2 offline WAV bank builder is tools/build_mb_doc_fx_bank.py. Its bank format matches these seven physical addresses, but **its file is not currently uploaded to FPGA**: the loader presently generates diagnostic PCM locally.

Do not merge experimental FX into golden M6.4.1 until physical audio and video stability, no-piano-regression and post-route timing are verified.
