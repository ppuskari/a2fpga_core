# M6.4 de-click candidate — Enhanced Mockingboard → Ensoniq DOC5503

**Created:** 2026-11-13  
**Branch:** `petar/mb-doc-m64-declick-20261113`  
**Parent:** `petar/mb-doc-m6-music-fx-routing-20261113`  
**Hardware status:** **RTL regression complete; not yet Gowin place-and-route or tested on Apple IIe.**

## Why M6.4 exists

The 2026-11-13 HDMI optical captures established that disabling the Ensoniq debug video overlay and native AY whole-chip FX bypass gave stable, good-sounding piano music. Small clicks remained at song boundaries and some individual note attacks. The M6 bridge previously sent an immediate DOC HALT and restarted the sample at calculated full volume; note-off could also immediately write zero. These abrupt phase/amplitude changes are plausible click sources.

The main M6 music/FX routing branch is preserved. **Do not change shared DOC5503 timing, PCM fetch, GS/Tool225 ownership, BL616 Stage 2, SSI263 WarGames Take10B or the -2 dBFS HDMI limiter for this experiment.**

## What changed

- `boards/a2n20v2-Enhanced/hdl/top.sv`: `MB_DOC_FX_AY_BYPASS_ENABLE=1'b0` (M6.3 stable physical baseline); video `DebugOverlay.ENABLE(1'b0)` (synthesis-time exclusion); `MB_DOC_DECLICK_ENABLE=1'b1` forwarded to the bridge.
- `boards/a2n20v2-Enhanced/hdl/mb_doc_bridge.sv`: optional `DECLICK_ENABLE` (default **off** when instantiating the module without an override), 8-bit per-voice DOC volume memories, pending-retrigger bits, attack step 16 and release step 12 per voice scan.
- New DOC notes program the sample, enter RUN at `VOL=0`, then ramp up over successive scans. Note-off and changed/same-pitch retriggers ramp the old oscillator down before DOC HALT. During fade-out, only VOL and CTRL are written; old pitch, WTP and RTS are held. A retrigger that remains pending starts only when the prior volume is zero. An asserted PSG reset still forces immediate silence.
- No new multiplier, shared audio-path filter or HDMI timing logic was introduced. The two original 8-bit piano amplitude operands are still multiplied once per scan; the de-clicker adds small 8-bit comparisons/add/subtract and 6 per-voice volume bytes.
- `tests/mb_doc/tb_mb_doc_declick.sv`, `tests/mb_doc/run_declick_test.sh` and `.github/workflows/mb-doc-m64-declick.yml` exercise attack/release/same-pitch retrigger and run original legacy tests for RES=0/1/2.

Attack and release durations are **scan-rate dependent**: the nominal 54 MHz, six-voice, 160-cycle host-spacing configuration gives approximately 2 ms for a full 208-volume attack and 3 ms for full release. These are not independent 1 ms wall-clock timers and must be checked with the hardware build.

## Hardware validation gate before more FX work

1. Preserve the exact previously stable M6.3 no-FX, no-overlay bitstream for comparison and rollback.
2. Use a separate checkout for M6.4. Restore the seven-zone piano memory, then Gowin build **FPGA only** and inspect routed LUT/BSRAM utilization and worst-case slack. Never reflash BL616.
3. Play SUGAR2, MINUET, WEASEL and rapid KEYBOARD; specifically listen to formerly clicked song end/new-note transitions, rapid same-pitch retriggers, note-off tails, timing or missed notes.
4. Record a comparable 44.1kHz HDMI optical WAV and compare to `cleannohalt.wav`. Watch for no video unlock, no 1-second dropouts, no unexpected overhangs in rests.
5. If click suppression is incomplete, examine loop boundaries of actual SynthLAB PCM zones and the 0→nonzero VOL edge; do not automatically add DSP filters or modify the HDMI pipeline. The previous detuned Sugar Plum notes are a separate pitch/timbre investigation.

## Windows PowerShell 5.1 (single-line commands)

```powershell
git clone --single-branch --branch petar/mb-doc-m64-declick-20261113 https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-m64
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-m64
```

```powershell
py -3 tools\extract_synthlab_piano.py --download
```

Gowin project: `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj`. Verify the two off switches and `MB_DOC_DECLICK_ENABLE=1'b1` before FPGA synthesis. Preserve the original R11 speech build and all golden GS bitstreams.

## Future M6.5 — independently sampled DOC FX

Only after M6.4 physical music validation passes: design the M6.2 diagnostic FX bank upload to *existing DOC SDRAM* at byte address `$2000..$6FFF` and trigger oscillator 6/7. Keep an explicit fallback policy and do **not** reintroduce the old per-chip native AY audio mux. Sample loading, address alignment, ownership and envelope/tail handling need dedicated RTL tests and a separate branch.

**This document is not a claim that the M6.2 sample bank already plays from hardware.**
