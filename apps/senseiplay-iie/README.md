# Sensei8 P0 — First 4-channel MOD → native a2fpga DOC playback test

This is the first **source + executable** attempt at a playable 8-bit Apple IIe tracker. It keeps the production-proven M641/A3 FPGA/MCU audio path unchanged and uses **Native DOC mode 2** (slot 4 `$C0C0..$C0CF`). It targets an ordinary ~1 MHz 6502/65C02 IIe. A TransWarp IIe or 16 MB AUX RAM is **not required**.

**Validation status:** The original four-channel demonstration MOD has been converted, a 3.5 KB 6502 binary has been assembled locally, and an executable 6502/register-bus simulator has verified DOC bank uploads, 64 note retriggers, the DOC enable register, stereo selection, and returning to BASIC. **This has not yet been listened to on real IIe hardware, compiled with Merlin32, or tested with real DOC timing.** Expect a P0 hardware iteration.

## 1. Protected hardware baseline

- Repository: `ppuskari/a2fpga_core`
- **Read-only hardware baseline branch by convention:** `petar/audio-m641-a3-hwvalidated-20261117`
- Proven commit: `b7ea7f6af45ac719062cdacfe2790b98c92567dd`
- Development branch: `petar/senseiplay-iie-mod-p0-20261117`

M641 Slot 6 cold autoboot, flash-persisted Original/Enhanced selection, double-stage `0x6F` verification, no-lock live switching, calibrated AY gain, hybrid SSI263 speech and the separate 128 KB DOC Mockingboard/FX work are **not altered**. This project does not build or flash gateware or the BL616 MCU.

## 2. Relationship to SenseiPlay / NinjaTrackerPlus

- `https://github.com/digarok/senseiplay` is the 65816 ProDOS 8 SenseiPlay frontend; `src/sp.s` loads and calls the separately distributed `NTPplayer`. It is not directly executable on a 6502 IIe (`XCE`, 65816 native mode, memory manager/banked pointers and `JSL`).
- Original audio engine: Jesse Blue's NinjaTrackerPlus; original archive is linked from `https://www.ninjaforce.com/html/products_ninjatrackerplus.php` and is **not embedded in SenseiPlay's Git repository**.
- This P0 is therefore a **new 6502-compatible direct-DOC playback engine**, derived from the *architecture and purpose* of SenseiPlay, **not a port of the complete NTP binary format or engine**. This explicitly avoids claiming that `.NTP` files play yet. The later `NTPLOAD`/`NTPPLAY` implementation will replace the host-side direct MOD conversion while keeping `A2SLOT` and `A2DOC`.

## 3. First hardware test (DOS 3.3, NOT ProDOS BASIC.SYSTEM)

**Important:** This P0 binary starts at `$2000` and returns with `RTS`, so the simple load-and-CALL test is for **DOS 3.3 Applesoft**. Do **not** `BLOAD` at `$2000` from ProDOS 8 `BASIC.SYSTEM`—that can overwrite the ProDOS system program. A bootable ProDOS 8 `SENSEI8.SYSTEM` wrapper will be the next packaging step once native DOC playback is confirmed.

1. Configure enhanced a2fpga Slot 4 to the DOC/Mockingboard card, and **save audio personality `NATIVE DOC` (mode 2)** in the BL616 menu. The player checks the slot identity `D`,`O`,`C` at `$C0C4..$C0C6` and readback `$C0C8=$A2`; otherwise it prints `SET A2FPGA AUDIO TO NATIVE DOC` and stops safely. Switch to Native mode live before starting if preferred; no Apple reset should be needed to change the FPGA personality.
2. On a DOS 3.3 disk image, use CiderPress or a similar disk image tool to add the provided `build/SENSEI8.BIN` as an Apple DOS binary file with **load address `$2000`** (8192 decimal). If the import tool asks for length, use the actual binary length, 3544 bytes for the bundled demo.
3. Boot DOS 3.3; run `BLOAD SENSEI8` (or `BLOAD SENSEI8,A$2000` where supported), then `CALL 8192`.
4. Expect `SENSEI8 P0 - FOUR CHANNEL DOC`, then the original four-voice test melody. Press any Apple II key to stop; playback also ends automatically after 64 rows. Check optical/HDMI audio for actual notes and left-right assignments. No speech is involved in native DOC mode.
5. If sound is absent, **do not rebuild FPGA/MCU blindly**. Check the menu still reports `NATIVE DOC`, `FPGA ACTIVE AUDIO NATIVE DOC`, A3 Verified. The first test determines whether native slot writes, waveform RAM uploads and oscillator control are actually working on the physical board.

## 4. Rebuild on Windows PowerShell 5.1 (one command per paste)

From the extracted package root, run:

```powershell
py -3 .\tools\make_demo_mod.py --out .\assets\sensei8-original-demo.mod
```

```powershell
py -3 .\tools\mod_to_s8m.py .\assets\sensei8-original-demo.mod --out .\src\module_data.s
```

```powershell
py -3 .\tools\s8asm.py .\src\sensei8.s --out .\build\SENSEI8.BIN
```

```powershell
py -3 .\tests\test_player.py
```

The Python assembler is intentionally restricted to exactly the source's 6502/Merlin-style subset; it emits a **raw code/data binary**, not a ProDOS/2MG disk image. Merlin32 can independently assemble the same `src/sensei8.s` plus `module_data.s` include; binary parity has not yet been checked against Merlin32.

For your own small 4-channel MOD, change only the converter input path. Regenerate `module_data.s` and reassemble. The converter refuses modules that exceed the first-run main RAM/sample bank limits.

## 5. Implemented P0 features

- 4 channels and 31-instrument ProTracker header, signatures `M.K.`, `M!K!`, `4CHN`, `FLT4`.
- Nonstreaming power-of-two DOC waveform tables in **bank 0**, up to 8 KB per instrument. Attack/sustain dual sample playback is not yet implemented; looping instrument PCM uses the source loop segment in P0, and nonlooping samples use DOC one-shot/HALT.
- Converted signed MOD PCM to unsigned offset binary; all normal sample bytes nonzero; one-shot final byte uses DOC `$00` HALT.
- Native DOC channel controls, frequency registers and direct sample-RAM uploads via `$C0C0..$C0C3`, with stereo pan L/R/R/L.
- PAL Amiga MOD period-to-DOC FC conversion, assuming 32 DOC oscillators enabled (`$E1=$3E`) and `DOC_SR=894886.25/34`.
- Row timing precomputed using ProTracker speed/BPM and exact rational frame counts, NTSC `$C019` ~60 Hz for ~50 Hz tick equivalent average; no timer IRQ required.
- Select `Fxx` speed/BPM and note-on, sample volume, `C00` cut. The `Cxx` update on existing held notes, slides, arpeggio, vibrato, delayed notes, loop jumps, full ProTracker effects and `.NTP` v0/1/2 parsing are **deferred**. Unsupported effects print a warning at conversion, never silently claim full fidelity.
- Full DOC 32-voice HALT on entry/exit so prior Enhanced DOC music cannot leak into Native mode when switched live.

## 6. Follow-on milestones, separate from Mockingboard FX work

1. Validate native DOC slot mode 2 on physical Enhanced IIe with this 3.5 KB test binary and the original demo MOD.
2. Add 6502 `NTPLOAD` for genuine `.NTP` v0/1/2 songs, preceded by obtaining the separately distributed NinjaTrackerPlus engine source and formal format definitions. Reuse the ProDOS 8 filename browser components of SenseiPlay after 8-bit adaptation; do not transfer 65816 `JSL` directly.
3. Add proper sample attack/loop swapping, event effects, 50 Hz interrupt-based timing if the FPGA can expose a reliable IRQ path, streaming for samples > on-card memory, then 128 KB bank 1 extension.
4. TransWarp IIe/65C816 optimization and RamWorks 16 MB AUX expansion are **optional later editions** for large songs and buffered sample transfers, not initial hardware dependencies.

All four source/build tools and test sources in this package are original reconstruction code; sample `.mod` was generated as an original test fixture and does not use external commercial music.