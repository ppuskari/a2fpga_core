# M3 Mockingboard Timing + ProDOS Audio Validation

**Experiment branch:** `petar/m3-mb-timing-prodos-suite-20261123`  
**Validated base branch:** `petar/m3-sd-sector-burst-20261123`  
**Base commit:** `72933b2709724bd8c89da030193d7df5d2c574b6`

## Reproduction (reported on ROM 03 IIgs)
- M3 a2fpga Enhanced FPGA and BL616 MCU loaded; physical Apple IIgs slot 4 set to *Your Card*.
- Virtual slot 4 Mockingboard only; audio mode *Original* with speech.
- On classic Mockingboard Demo Disk 1 `.po`: at IIgs Fast (2.8 MHz), title appears and sounds reasonable, then upward text/sound slide pauses twice and enters monitor.
- Same disk at IIgs Normal (1 MHz) plays correctly.
- **Do not assume the demo is accelerator-compatible**: many period effects use CPU-rate-dependent delays. Test hardware and application timing separately.
- Desired: correctly synchronized VIA/SSI263 behavior even when CPU executes faster than slow I/O cycles (e.g. future accelerators approaching 16 MHz), subject to actual accelerator bus implementation.

## Reference hardware diagnostics: mb-audit
- [mb-audit source / detailed coverage](https://github.com/tomcw/mb-audit)
- [v1.61 release](https://github.com/tomcw/mb-audit/releases/tag/v1.61)
- [v1.61 140K ProDOS-order disk image](https://github.com/tomcw/mb-audit/releases/download/v1.61/mb-audit-v1.61.po)
- Covers slot scanning, both 6522s, timer T1/T2, underflow/IFR/IER, IRQ, 65C02/65816 read side-effects, AY register reads/writes, SSI263 timing and false-read effects, and manual L1/L2/L3 + R1/R2/R3 tones.
- Author's IIgs instructions **specify System Speed=Normal and Slot 4=Your Card**. Run this first for comparable baseline. Fast-mode results are exploratory, not automatically RTL defects.
- Record first failure *exactly*: `Test: CC:TT:nn`, `Expected`, `Actual`, slot, IIgs ROM and CPU mode. Note if false-read tests or speech detection are intentionally unsupported in the FPGA.

## Six-voice musical reference
- [Vince Weaver's six-channel PT3 library](https://github.com/deater/dos33fsprogs/tree/master/music/pt3_lib_6ch)
- [Ready-to-run 140K DOS 3.3 demonstration](https://github.com/deater/dos33fsprogs/blob/master/music/pt3_lib_6ch/release/pt3_lib_ch6.dsk)
- Demonstration uses two 3-channel PT3 arrangements of DYA's *Dance of the Dead*, one per AY PSG. Useful for simultaneous notes, mixer/noise, envelope and periodic VIA IRQ exercise.
- Library's `LICENSE` explicitly offers **0BSD or GPL-2.0-only for code**. **Song rights are separate**; retain attribution and verify before redistributing an integrated music image.
- On IIgs, begin at Normal speed. Retest at Fast as a separate data point; the specific player may itself have cycle-dependent behavior.

## Planned original, standalone ProDOS 8 disk
Separate from `a2media.system` and without changing the M3 audio/J2R11/SD burst path. Prefer stock ProDOS 2.4.3, `.po`, 140KB, 65C02-safe 6502 binary for IIe/IIgs, virtual Mockingboard slot 4 selectable.

Potential contents of `MBTEST.SYSTEM` menu:
1. **VIA register bus integrity:** left/right DDR, ORA/ORB, IFR/IER and mirror decode; repeat thousands of transactions and report first failure.
2. **Timer and interrupt integrity:** 6522 T1/T2, one-shot/free-running, expected timer periods, IRQ acknowledge/re-arm, burst access/CA1 status.
3. **Six-voice channel check:** isolate L-A/L-B/L-C and R-A/R-B/R-C; stereo check and six-note chord.
4. **Effects:** AY tone/noise mixer, envelope shapes, volume ramps, rapid retrigger, percussion/noise bursts, PSG silence.
5. **Real song:** PT3 six-channel playback on both PSGs with original score/redistribution rights checked; reference source is the Vince Weaver player.
6. **SSI263:** controlled phoneme sequence, A/R/readback and right-VIA CA1/IRQ, with MCU DSP only producing audio; avoid assuming diagnostic overlays represent physical chip registers.
7. **Combined stress:** simultaneous six-channel PT3 + speech + periodic VIA IRQ; test both Original and Enhanced personalities without introducing a transport dependency.
8. **Speed matrix:** IIe Normal; IIgs ROM 03 Normal, Fast; accelerated CPU where available, with explicit distinction between physical slow I/O cycles and instruction execution speed.

Log expected/actual, timer readings, IRQ counts, speech timeout, mode, and runtime, ideally printable/copyable from 40/80-column display. Do not change protected golden FPGA flash; use volatile FPGA bitstream for experiments. Preserve synthesized ROM/SynthLAB assets and M3 SD burst, M2 mailbox and jukebox.

## Initial test sequence
1. M3 unchanged at IIgs Normal: MB-Audit v1.61, log detection and first failures.
2. M3 unchanged at IIgs Fast: rerun MB-Audit, log deviations with the author's Normal-speed warning in mind.
3. M3 unchanged: six-channel PT3 DOS disk at Normal and Fast, listening and watching for IRQ/pattern problems.
4. Only after collecting results, instrument the FPGA bridge/6522/IRQ paths and add deterministic simulation for back-to-back slow-I/O cycles with rapid CPU instruction phases.
5. Build original ProDOS disk from tested sources and compare it against external reference players.

## Current status
Only the branch and this experiment note are prepared. **No gateware/MCU change, binary ProDOS disk, synthesis, simulation, or on-device validation is represented as complete.**
