# M6.6a — Two 64KiB DOC sound banks; isolated MB-DOC merge candidate

**Date:** 2026-11-16
**Branch:** `petar/mb-doc-m66a-dual-bank-fx-20261116`
**Based on:** `petar/mb-doc-m65b-procedural-fx-osc67-20261116`
**Gold baseline:** `petar/mb-doc-m641-coherent-20261113` — direct Vizio HDMI and Vizio optical `641good.wav` verified.
**Status:** RTL integration and simulation. Gowin synthesis/PnR/hardware listening NOT yet performed.

## Why this build is isolated

A separate workstream is implementing BL616 startup mode selectors and an Apple IIe 128K ProDOS 8 SenseiPlay/NTP player. This branch deliberately DOES NOT touch the MCU console, BL616 firmware, SSI263, slot-4 register protocol, selected startup audio mode, SenseiPlay player, GS Sound Tool/Tool225, or HDMI packetizer. The new code concerns only exclusive MB-DOC sound memory and DOC oscillator FX bank selection. Do not merge until both workstreams independently complete their hardware tests.

## Physical sound RAM architecture

`sound_glu.sv` already supports the original 64KiB DOC sound address space and an opt-in 128KiB A2FPGA extension. In the current Enhanced design `USE_BSRAM=0`, so sound RAM lives in **external DDR3**. No new 64KiB Tang Nano BSRAM block is allocated.

The existing GS/IIgs extension requires explicit software unlock key `A2FP` and $E6 command. That behavior is retained unchanged in GS mode. In **MB-DOC mode only**, new `MB_DOC_128K_AUTO_ENABLE=1` allows RTS[6] oscillator bank selection once the bridge raises the synchronous `mb_bank1_ready_o` signal, which occurs *after Bank1 preload completes*. While the bank is being filled, read fetches are safely held to Bank0. The new bridge never writes A2FP extension-key bytes to the CPU address space.

Bank addressing is at the **32-bit SDRAM word address** level:
- Bank0: words $0000–$3FFF; byte addresses $0000–$FFFF.
- Bank1: words $4000–$7FFF; byte addresses $10000–$1FFFF.
- Existing piano: Bank0 byte $0000–$15FF, 5632 bytes, 1408 words.
- Experimental FX: Bank0 byte $2000–$6FFF, 20KiB, 5120 words, present from M6.5b.
- Experimental alternate FX: Bank1 byte $12000–$16FFF (in-bank $2000–$6FFF), 20KiB, 5120 words. Variant sample texture, same WTP/WTS and terminal DOC HALT bytes.
- Other space in both 64KiB banks remains **uninitialized / reserved** in this experiment. Do not assume all 128KiB bytes are valid samples yet.

The FX wave generator is reused across both passes (no second 20KiB ROM). On Bank1 pass it varies the noise texture deterministically without moving sample addresses or their final $00 markers.

## Oscillator selection

DOC oscillators 0–5 always read Bank0 and use the unchanged seven-zone piano tables, voice scan, de-click, coherent AY publication and pitch divider. They NEVER receive the RTS[6] bank-select bit.

DOC oscillator 6 remains left FX and oscillator 7 remains right FX, but either oscillator can now play an effect from either sound bank, selected per *patch*:
- Bank1: explosion, laser, cymbal.
- Bank0: kick, snare, tom, hi-hat.

The experimental patch classification is heuristic and not a complete emulation of original AY continuous noise/envelope behavior. No new voice has been created; the maximum active DOC oscillator budget stays at eight. Current FX pending policy is still one last-wins event per AY chip, not a lossless event queue.

## Test gates

`.github/workflows/mb-doc-m66a-dual-bank.yml` runs:
- All M6 original AY and piano, M6.4 de-click and M6.4.1 coherent publication regression suites.
- M6.5a FX event correctness and M6.5b Bank0 sampled FX path.
- M6.6a dual-bank preload test: 11648 total SDRAM words, Bank0 $0800–$1BFF plus Bank1 $4800–$5BFF, no misaddressed writes, Bank1 data differ from Bank0, bank readiness only after completed writes, and exact OSC6/OSC7 bank-select bit in RTS.
- Static GS-lock gate: MB auto-bank path cannot bypass GS's existing unlock protocol.

CI does NOT synthesize a Gowin bitstream or prove the 54MHz logic/pixel STA, audio quality, actual LCD HDMI link or physical DDR3 banking. A successful CI is a source-level hardware candidate, not a final golden build.

## PowerShell 5.1 single-line checkout

```powershell
git clone --single-branch --branch petar/mb-doc-m66a-dual-bank-fx-20261116 https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-m66a
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-m66a
```

```powershell
py -3 tools\extract_synthlab_piano.py --download
```

Gowin project: `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj`.

Confirm the generated SynthLAB piano bank fingerprint 170BB8B3. Save the M6.4.1 good FPGA `.fs` and all PnR/timing reports. Build the **FPGA only** from this independent checkout; verify place/route and post-route setup/hold closure before flashing. Do not touch BL616 firmware or MCU startup menu.

## Hardware test order

1. Direct Tang Nano HDMI to Vizio panel, optical audio from Vizio to Mac Pro. Keep broken Amazon splitter/extractor removed.
2. Power up and check piano with no FX, play SUGAR2, MINUTE, WEASEL in loops and compare to `641good.wav`. Confirm neither piano quality nor stereo notes regress, with no video instability, note drops or clicks.
3. Play demo title and FX. The original procedural samples are intentionally simple. Listen for laser/explosion/cymbal (new Bank1 variants) versus kick/snare/tom/hihat (Bank0). They should play without stopping music.
4. Verify right and left FX independently, repeated bursts and no cross-channel stolen piano notes. Any audible FX difference between this and M6.5b is expected; melody/piano differences are not.
5. Save waveform recording, post-route timing report, BSRAM utilization, DSP/LUT count, boot-to-audio time and any observed sound glitches. If anything bad occurs, restore golden M6.4.1 bitstream.

## Merge strategy with MCU startup selector and SenseiPlay

Let the other workstream finish and hardware-validate first. Merge at the common parent with parameterized feature switches:
- M6.6a contributes `sound_glu` MB-only auto-bank gate and ready handshake, new bridge FX bank1 loader/RTS selection and waveform variant.
- MCU menu contributes mode-state selection at startup; do not depend on yet-to-be-defined menu values or change its mode enum from this branch.
- 8-bit SenseiPlay/NTP player may later request instrument patch/bank IDs, but no such software-visible register interface is introduced in M6.6a.
- Preserve GS mode bank security/compatibility and the stable normal Mockingboard, DOC Enhanced, Native DOC and shared-mode ownership choices.

Next steps once hardware stable: populate the remaining 128KiB with user WAV libraries and instrument directory, performance-test nonblocking patch upload while streaming, add true AY-parity continuous noise and envelope-mixer behavior, and expand multi-FX voice allocation without losing note events.
