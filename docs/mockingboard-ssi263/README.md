# Mockingboard SSI-263 / SC-02 speech — isolated A2FPGA development

**Branch:** `petar/mb-ssi263-kue-m-isolated-20261106`
**Branch base:** `ppuskari/a2fpga_core` `main` (NOT any MB-DOC piano or experimental Ensoniq branch).
**Status:** **P0 CPU-bus/control/A-R/CA1 interface only**. Icarus standalone RTL test PASS. **No synthesized speech audio or Gowin/hardware validation yet.**

## Why this project

The original Enhanced A2FPGA Mockingboard implementation contains two 6522 VIAs and two YM2149 tone generators, but neither the SSI-263 speech synthesizer nor the active-low A/R -> VIA CA1 wiring. Apple II software using SSI speech sees a nonfunctional socket. Keep the original six AY audio channels, and eventually add speech over the existing HDMI audio mix.

Reference project [kue-m/mockingboard-pico](https://github.com/kue-m/mockingboard-pico) implements an SSI-263 emulator running on a dual-core RP2350 and mixes speech + AY music. It is MIT licensed, copyright 2026 Kitcat. Its vendored [ssi263-speech engine](https://github.com/lprazdnik/ssi263-speech), by Tamas Geczy (MIT, 2026), implements the multi-formant voice with floating-point arithmetic, phoneme ROM, and glottal/noise sources. The Pico project deliberately uses a clean-room glottal source instead of MAME's GPL waveform. Observe *both* MIT notices if porting any substantial vendor code. No C source or ROM has been copied into this P0 branch.

## Mockingboard C compatibility

First target: one SSI-263 speech socket at card offset `$40-$7F` (`$Cn40` canonical), A6 asserted and A7 clear; register select uses `A2:A0`. In this range it shadows the left 6522's VIA mirrors. Writing offsets 4, 5, 6, and 7 aliases SSI register 4. Readback bit D7 reflects A/R **request** (1 means ready for the next phoneme). Physical active-low A/R is wired to the *left* VIA's CA1 input; the VIA edge detector/IFR/IER then handles interrupts.

By comparison the RP2350 Pico design models two SSI sockets, selected by A5 and A6. A standard Mockingboard C needs one; dual sockets/Phasor options should be deliberately selectable in a later phase, not silently exposed in a simple Mockingboard C.

The normal VIA mirrors outside the speech range are unchanged. Disabling the SSI parameter leaves the original card unchanged.

## P0 implementation

- `hdl/mockingboard/ssi263_slot.sv`: detect `$Cn40-$Cn7F`, produce one write strobe for a held Apple bus transaction, return status D7, and expose active-low A/R to left VIA CA1.
- `hdl/mockingboard/ssi263_control.sv`: five register bank (R4 aliases at offsets 4-7), R0 repeated-phoneme retrigger, CTL bit 7 power-down and 1->0 startup, rate in R2 bits 7:4, coarse chip duration model based on the SSI reference: frame XCK cycles = 4096*(16-rate). Mode1 duration = one frame; other modes = (4-duration_code) frames. A/R requests the next phoneme when its timer completes, but mode0 does not request. This is NOT the full chip's glide, lookahead, phoneme-to-phoneme articulation, or filter behavior.
- `hdl/mockingboard/mockingboard.sv`: left VIA uses speech A/R instead of constant-high CA1 when enabled; overlapping VIA accesses in the speech region are gated. Both YM2149s and existing audio outputs remain unchanged.
- `boards/a2n20v2-Enhanced/hdl/top.sv`: experiment enables `MOCKINGBOARD_SSI263_ENABLE = 1` for the Enhanced board, independent of the existing `MOCKINGBOARD_ENABLE`. No DOC/Ensoniq or MCU modifications.
- `boards/a2n20v2-Enhanced/a2n20v2_enhanced.gprj`: registers SSI front-end sources for Gowin.

This is **NOT yet an audible SSI emulator**. The speech DSP is absent; the control interface alone can be useful for early software detection and interrupt diagnostics but will not speak, and some software may depend on more precise A/R timing.

## First tests

`tests/mb_ssi263/tb_ssi263_slot.sv` and `.github/workflows/mb-ssi263.yml` use Icarus Verilog to verify:
- SSI socket at `$Cn40`; no speech override at `$Cn20` or the right VIA `$Cn80`.
- D7 status starts 0 and rises to 1 after the tested 8192-XCK mode2 phoneme period.
- CA1 active-low output falls at that transition (the VHDL VIA captures this as a falling-edge IFR bit).
- R0 write clears the request and restarts the timer; CTL=1 powers down.
- Mode0 never requests another phoneme; disabling the card isolates A/R.

These tests **do not validate mixed VHDL+SV top-level Gowin synthesis, actual Apple slot write-data timing, or a real VIA interrupt on hardware**. A useful next testbench is to exercise the full VIA and speech bus with actual late Apple writes and CA1 IFR masking.

## Planned P1: audible fixed-point formant core

Port the *algorithm* from the MIT `ssi263-speech` C reference, not the RP2350 code verbatim:
1. Add a phoneme-start strobe on R0 writes / CTL falling edge; retain the 64 phoneme x 29-bit die-decoded parameter table with MIT provenance.
2. Implement a time-multiplexed fixed-point filter pipeline for resonances F1/F2/F3 and the additional nasal/fricative paths, a deterministic noise source and a non-GPL glottal source. Preserve oscillator phase and filter memory across phonemes.
3. Implement the actual articulation and pitch transitions, closure/release bursts, A/R early lookahead, rate and inflection. Generate 44.1 or 50 kHz signed PCM and mix with the two original AY channels before HDMI; use wide signed accumulation, headroom, and overflow telemetry.
4. Build a reproducible numerical regression comparing PCM (or envelopes/formants) to the upstream MIT C implementation, plus A/R software/hardware tests using Berzap!, Sweet Micro Speech Development System, Willy Byte, and SSI-263 speech test utilities.
5. Keep AY music native; do not couple this speech work to the MB-to-DOC instrument-bank experiments until separately hardware-proven.

A possible alternative is to run the proven C formant engine on the Enhanced BL616 and stream PCM to the FPGA, but the existing MCU-to-FPGA bandwidth/latency path must be characterized before selecting that architecture. **The P0 branch makes no assumption that BL616 can already deliver low-latency audio.**

## Windows PowerShell 5.1 / Gowin

To inspect this isolated branch without modifying your successful DOC piano checkout:

```powershell
git clone --branch petar/mb-ssi263-kue-m-isolated-20261106 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-ssi263
```

Project: `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj`

The P0 interface has no speech output. You may run Gowin synthesis to measure resources and check for dropped SSI modules. **Do not replace the known-good speech/music bitstream expecting voice output from this P0 source.** The BL616 bootloader and host firmware are not part of this work.

