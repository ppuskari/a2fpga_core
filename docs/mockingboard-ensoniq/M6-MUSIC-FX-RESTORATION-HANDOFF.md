# M6 Mockingboard / Ensoniq DOC music and FX restoration — handoff

**Started:** 2026-11-13  
**Branch:** `petar/mb-doc-m6-music-fx-routing-20261113`  
**Based on:** `petar/ssi263-p10r11-spi-suspend-wargames-20261111` (last complete R11 mixed music + SSI-263 speech)  
**Status:** First music/FX routing correction committed and verified in RTL simulation. Sample-bank builder and diagnostic one-shot FX samples prepared. **Not yet Gowin routed or heard on physical Apple IIe.**

## User intent and non-negotiable constraints

- The preferred WarGames SSI263 voice is **finished**, at Take 10B (native R4=$E5 through A, R4=$E4 for GAME, K2+KV1). Preserve original SSI speech, carrierless idle, SPI suspend/resume, BL616 USB HID/TAB and the 180-second console timeout. **Do not rewrite MCU Stage 2 or reflash BL616 as part of M6.**
- Return to the **Enhanced Mockingboard → existing single Ensoniq DOC5503** replacement on Tang Nano 20K Enhanced, Apple IIe slot 4.
- The native AY has 3 square-wave generators per chip, shared noise and envelope; no PCM samples. The experimental Ensoniq bridge has **seven real SynthLAB piano SUSTAIN** zones, but titleFX native AY bypass currently switches the *entire stereo side* to chip-style square waves.
- User wants classical demo tracks SUGAR2, MINUTE, WEASEL to sound like the **excellent sampled-piano free-play KEYBOARD**. Keep missing-note/restrike and note-off debugging. Preserve recognizable scrolling title/explosion effects.
- Later create a serious DOC sound bank for **piano hammer attacks/sustains, bass/strings/organ and actual sampled explosions/percussion/laser/cymbal**, with filtering, effects and track/player profiles. Do not confound this with original AY program having instrument IDs (it does not).
- Preserve exclusive GS/DOC vs MB/DOC ownership, golden GS/Tool225 64/128K, no duplicate DOC engine, unchanged sample-fetch path and -2dBFS HDMI limiter.

## M6.1 routing bug / first fix

Previously `boards/a2n20v2-Enhanced/hdl/mb_doc_bridge.sv` unconditionally set `fx_ay_l_o/r_o` when `mixer==8'h1C && amplitude_A!=0 && amplitude_B!=0`. In `top.sv`, that bit controls a **whole-chip audio mux**, replacing all DOC voices on that side with native AY. Ordinary two-voice music can match that state; this was a plausible source of the unwanted chiptune sound.

Now `mixer=$1C` is **not** sufficient. For title sweeps, the bridge detects the observed behavior of the original `BLOCK GRAPHICS` IRQ handler (source `$8194`): left/right AY R0 and R2 low bytes **each decrement by one** and R6 noise period **increments by one** within one AY write batch. Only then is native-AY title FX bypass enabled and held for **70 ms** at the 54 MHz logic clock, long enough to cover the demo's measured ~51.8ms timer intervals. The flags are cleared at R6 writes, PSG RESET cancels the hold, and each chip is independent.

The existing actual-noise and three-envelope title classifications remain native AY for compatibility. **This is still per-chip routing**; future per-voice DOC percussion will replace it. It is not a universal AY music/FX classifier, and it has not yet been validated on physical Apple IIe.

The regression in `tests/mb_doc/tb_mb_doc_bridge.sv` now verifies:
- a normal fixed-volume two-channel MCS-like chord at mixer $1C **does not bypass piano**;
- synchronized R0/R2 downward + R6 upward title sweep **does bypass**;
- title bypass expires and does not stick; PSG reset releases it;
- native AY noise + triple-envelope title effects remain; keyboard $3E remains piano;
- independent left/right routing, usual DOC period-1 rests, A440 piano envelope, same-pitch retrigger, all six voices.

The CI uses **real Icarus HDL simulation** for all three DOC RES=0/1/2 settings, restores the checksum-verified SynthLAB piano memory from Apple's existing publicly hosted disk image, runs native YM Verilator envelope tests and checks the R11 combined speech mux remains present. This is not a Gowin timing-closure test or real HDMI recording.

## M6.2 First DOC FX sample bank tooling (NOT in FPGA playback yet)

`tools/build_mb_doc_fx_bank.py` is a self-contained, deterministic *offline* compiler, supporting:
- `--input-dir` containing user-provided PCM WAVs named `explosion.wav`, `kick.wav`, `snare.wav`, `tom.wav`, `hihat.wav`, `laser.wav`, `cymbal.wav`;
- `--fixtures` creating **original diagnostic synthesized waveforms only**, expressly NOT production-quality FX, plus preview WAVs;
- `mb_fx_bank.bin`, `mb_fx_bank.mem` (little-endian 32-bit hex words for SDRAM loader), and `mb_fx_bank.json` with patch names, addresses, WTP/WTS and checksums.

The reserved first-bank sound RAM region is **$2000–$6FFF**, 20KiB, leaving existing piano at $0000–$15FF intact and some spacing. This is only a proposed layout until the actual host SDRAM loader and oscillator allocator are implemented and measured.

| Patch | DOC byte start | Size | WTP | WTS | Policy |
|---|---:|---:|---:|---:|---|
| explosion | $2000 | 8192 | $20 | 5 | one-shot, long noise/rumbly |
| kick | $4000 | 1024 | $40 | 2 | one-shot |
| snare | $4400 | 1024 | $44 | 2 | one-shot |
| tom | $4800 | 1024 | $48 | 2 | one-shot |
| hihat | $4C00 | 1024 | $4C | 2 | one-shot |
| laser | $5000 | 2048 | $50 | 3 | one-shot |
| cymbal | $6000 | 4096 | $60 | 4 | one-shot |

Each DOC one-shot table terminates with **exactly one $00 (HALT)** at its final byte. Source samples are offset-binary 8-bit, clipped to [$01,$FF] before that terminal marker. Tables are size/alignment compatible with WTS; frequency/FC playback and release durations **must be calibrated on the real DOC**. Tests confirm no premature HALT, deterministic audio bytes and bank checksums. The reference 16kHz in generated WAVs is a *source calibration*, not a DOC playback clock. Audio samples are not redistributed in GitHub.

**IMPORTANT:** This bank is **not loaded or triggered by the current FPGA bitstream**. Do not misinterpret the diagnostic preview ZIP as a working replacement for explosions. The bridge's current SynthLAB loader is still only 5632 bytes; additional ~20KB FPGA block RAM would be expensive. Decide how to upload the bank to the already-existing DOC SDRAM with minimal BSRAM/MCU disruption before integrating it.

## Planned next hardware increments

1. **Build FPGA from this M6 branch**, without changing MCU firmware, test real Apple IIe slot-4 Demo Disk 1. Capture short optical HDMI sound for boot title, KEYBOARD, SUGAR2, MINUTE, WEASEL. Observe/debug `mb_fx_ay_l_w` / `mb_fx_ay_r_w` and DOC voice HALT/restrike events. Confirm classical songs are now continuously on DOC and that the actual title effects remain. Compare to original native AY/Mockingboard and saved P4/P5 bitstream. Keep clipping diagnostics.
2. If pitch/rhythm still sounds chip-like, investigate **sustain-only piano and missing transient note attacks** separately from bypass. Explicit note triggers may need a policy for the MCS software-volume envelopes; compare real AY register traces and note counts; do not assume the classifier correction cures timbre.
3. Design **DOC FX bank loader** into sound RAM, validate word/byte order, bank ownership and waveform fetches. Allocate first FX to DOC oscillator 6/7 (the two currently halted slots) rather than changing E1's current scan of eight oscillators and invalidating the calibrated AY-to-DOC frequency `FC≈93623/P`.
4. Introduce a **sample-trigger event path** from native AY noise/sweep recognition to DOC FX voices. For initial backward compatibility allow current native AY FX when no sample is loaded. Replace explosion, percussion and sweeps incrementally; test repeated triggers, sample zero-HALT, stereo, clipping and tail behavior.
5. Add explicit per-channel **instrument/patch profile** separate from ordinary AY registers, then MBPLAY track player. First ensure the unmodified MCS songs faithfully use real piano; implement per-track patch IDs only after that music gate passes.
6. Add attack+loop sustain zones for piano and more instruments; consider SRC/IR sample licensing and input-file provenance. Offline-filter sample variants initially; no generic resonant realtime filter is present inside the DOC5503. Add FPGA filter blocks only after resource/timing measurements.

## Windows PowerShell 5.1: work in a separate checkout

Use single-line commands (multi-line console pastes have previously reversed/broken).

```powershell
git clone --single-branch --branch petar/mb-doc-m6-music-fx-routing-20261113 https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-m6
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-m6
```

```powershell
py -3 tools\extract_synthlab_piano.py --download
```

```powershell
py -3 tools\build_mb_doc_fx_bank.py --fixtures --out C:\AppleIIgsDev_02\a2fpga-mb-doc-m6\artifacts\fx_bank
```

```powershell
py -3 tests\mb_doc\test_fx_bank.py
```

Gowin: `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj`. Set `AUDIO_MODE_MB_DOC=1` in the experimental build, with native AY FX bypass still enabled, and preserve the R11/P4 known-good bitstreams. Build/flash **FPGA bitstream only** after checking resource & timing stats. Never reflash BL616 Stage 2 from a music-only branch.

### New-context resume prompt

> Resume my a2fpga Enhanced Mockingboard → Ensoniq M6 music/FX restoration from branch `petar/mb-doc-m6-music-fx-routing-20261113`. Read `docs/mockingboard-ensoniq/M6-MUSIC-FX-RESTORATION-HANDOFF.md`. M6.1 changed the overly broad mixer=$1C AY FX bypass to a verified R0/R2-down + R6-up title sweep detector, with simulations passing all DOC resolution modes. M6.2 created a test-only seven-slot DOC one-shot FX sample-bank generator for explosions and percussion; **not yet wired to playback**. Next: validate Demo Disk 1 KEYBOARD/SUGAR2/MINUTE/WEASEL/title on physical Apple IIe while preserving R11 speech and the golden WarGames Take10B; then integrate FX bank SDRAM upload and OSC6/7 triggering. No BL616 reflash, keep old FPGA bitstream reversible.
