# M6.4.1 coherent DOC musical-state publication — handoff

**Branch:** `petar/mb-doc-m641-coherent-20261113`  
**Base:** `petar/mb-doc-m64-declick-20261113`  
**Date:** 2026-11-13  
**Status:** Icarus RTL regression passed; **Gowin route and physical Apple IIe HDMI audio testing are still required**.

## Why

Hardware audio on the stable no-FX/no-overlay M6.4 build retained short note-end clicks and a larger stereo impulse at the repeat of Sugar Plum. Analysis of the user's original DOS 3.3 demo disk identified the MCS player's register output loop at `$86C8`. That loop writes AY register indices **0 through 14** in order, **left then right** for each index. It consumes about 79 6502 cycles per index, about 77us at the Apple II clock, and about 1.16ms for the complete burst. The two-byte tone period can therefore temporarily contain one old and one new byte. The old DOC scanner could classify that temporary pitch as a new note or sample-zone transition and issue an unnecessary HALT/WTP/RTS/retrigger.

The native AY/Mockingboard continues to receive every write as it arrives. Compare `kue-m/mockingboard-pico`: its C emu2149 also updates individual AY writes but updates continuous PSG oscillators, whereas our DOC instrument conversion can translate an intermediate state into a fresh sampled-piano strike. The **DOC-only** publication stage solves that distinct problem without modifying AY emulation.

## Implementation

### Bridge: `boards/a2n20v2-Enhanced/hdl/mb_doc_bridge.sv`

New synthesis parameters:

- `COHERENT_PUBLISH_ENABLE` defaults to **off** on a bare bridge instance, preserving legacy test behavior.
- `COHERENT_IDLE_CYCLES=10800` gives an approximately **200us** no-write timeout at 54MHz.

An immediate `ay_regs[2][16]` shadow continues to receive the original AY write strobes and to feed FX detection. The new `doc_regs[2][16]` snapshot is the only register state used for the six melodic DOC voice scans.

Each chip independently tracks ascending register indices R0..R14. An unbroken full sequence publishes all 16 shadow registers at R14, including the just-written R14 value. This is the **MCS fast path**. If software writes individual registers, partial frames, or a different order, the pending snapshot is published after 200us of inactivity; the sequence detector then resets. A PSG reset clears both shadows and any pending publication for its chip immediately. Live native YM2149 envelopes, actual AY writes, reset semantics, and raw AY FX detection are untouched.

This does **not** guarantee one transaction for every conceivable non-MCS player. A program that spaces two related byte writes over more than 200us may cause two fallback publications. That is an explicit compatibility tradeoff to limit latency.

### Enhanced top: `boards/a2n20v2-Enhanced/hdl/top.sv`

```systemverilog
parameter bit MB_DOC_FX_AY_BYPASS_ENABLE = 1'b0,
parameter bit MB_DOC_DECLICK_ENABLE = 1'b1,
parameter bit MB_DOC_COHERENT_PUBLISH_ENABLE = 1'b1,
```

`DebugOverlay.ENABLE(1'b0)` stays in effect at synthesis. No changes to the single DOC5503 core, original piano RAM content, speech mux, SSI263/WarGames Take10B, MCU Stage 2, GS/Tool225, or -2dBFS HDMI limiter.

## Automated simulation

New: `tests/mb_doc/tb_mb_doc_publish.sv` and `tests/mb_doc/run_publish_test.sh`. The synthetic MCS register data is generated in the testbench; no copyrighted disk image is checked into Git.

Tests for all DOC RES 0, 1 and 2:

1. Interleaved left/right R0..R14 writes remain hidden from DOC until frame publication.
2. Intermediate pitch `$01F0 → $0120 → $0220` is never published.
3. Intermediate mixer/volume changes must not publish or cause a DOC HALT.
4. Song end simultaneously clears both active amplitudes via the MCS R14 publication, **without** hardware reset.
5. Repeating a song starts new notes correctly after the prior release.
6. Non-MCS R0/R1 single-register updates commit together after bounded quiet time and leave the other chip untouched.
7. Aborted register bursts flush after timeout; per-chip PSG reset clears only its side.
8. Existing M6 routing, M6.4 de-click and AY capture tests continue to pass with coherent publication disabled (separate regression).
9. Stable hardware configuration and R11 speech mux markers remain present.

Workflow: `.github/workflows/mb-doc-m641-coherent.yml`. All tests are Icarus structural/command-sequencing tests; they **do not prove the audible click is fixed**.

## Windows 11 PowerShell 5.1, all single-line commands

```powershell
git clone --single-branch --branch petar/mb-doc-m641-coherent-20261113 https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-m641
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-m641
```

```powershell
py -3 tools\extract_synthlab_piano.py --download
```

Gowin FPGA project: `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj`.

### Gate before flashing

- Preserve the working M6.4 bitstream as an immediate rollback.
- Confirm audio mode `AUDIO_MODE_MB_DOC=1`.
- Confirm the three switches above and `DebugOverlay.ENABLE=1'b0`.
- Inspect LUT/BSRAM usage, timing closure/slack for the 54MHz logic, pixel and 135MHz HDMI domains. Do not deploy a timing-failing build.
- **FPGA bitstream only. Do not reflash BL616.**

### Hardware A/B validation

1. Boot Demo Disk 1 on Enhanced Apple IIe slot 4; record optical HDMI audio at 44.1kHz stereo.
2. Play Sugar Plum Fairy through at least 3 repeats (about 38.16s per repeat), then MINUET and WEASEL, then rapid KEYBOARD repeated-note exercises.
3. Check the prominent repeat-boundary stereo click (previous recording around 38.294s, roughly 60ms before first note), plus frequent short note-ending/inter-note clicks. Compare relative phrase positions rather than absolute WAV timestamps.
4. Verify no extra missing/retriggered piano notes, unexpected lag or detuning; the slightly flat Sugar Plum timbre remains a separate sample-zone investigation.
5. Perform a 20-minute soak for HDMI sync stability and full-stereo audio dropouts. The timing-sensitive overlay must remain disabled.
6. If clicks persist, narrow the remaining source to actual PCM/sample zero-marker edges, DOC VOL/CTRL/HALT sequencing, live YM envelope transitions, or global mixer/speech/reset behavior. Use compact off-screen counters/traces, not the old video overlay.

## Next stage after hardware validation

Only after this gate: (a) fix any residual audio discontinuities using actual captured PCM transitions and/or event trace; then (b) proceed to isolated M6.5 FX sample bank SDRAM upload and OSC6/7 one-shot trigger routing, preserving all six melodic voices. The M6.2 diagnostic seven-sample FX bank is **not yet playing** in any current FPGA bitstream.
