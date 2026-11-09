# P10-R7A — SSI-263 speech transition cleanup and conditional idle FPU relief

**For** `boards/a2n20v2-Enhanced` **ONLY**. Branch:
`petar/ssi263-p10r7-speech-transitions-idle-20261109`.

## Motivation / live-hardware evidence

- R6 at **22,050 samples/s**, 16-bit PCM, with 44,100Hz HDMI output, runs
  at expected average rate and showed `G=0, OVR=0, UND=0` during a
  roughly 12-minute post-demo observation.
- Onset and offset of audible speech may have an unnecessary short
  white-noise-like burst / click. Do NOT confuse this with intentional
  SSI-263 unvoiced phonemes or plosive releases.
- The BL616 continues performing expensive Pico C DSP and sending
  zero/silent PCM while the SSI chip remains powered but no new Apple
  SSI write is sent.
- Native-SSI recording differs in high-frequency content; analog/
  YouTube path differences are not independently controlled. Global
  noise-gain reduction or low-pass filtering is NOT enabled by default.

## Changes in R7A

**MCU ONLY**. The original **P10-R6 FPGA bitstream**, 22.05kHz XFER
protocol and HDMI audio/piano/AY/IIgs graphics are unchanged. The
Enhanced USB HID keyboard and eight-port hub limits are untouched.

1. **Gentle 2.5ms PCM attack ramp** after *18ms of near-zero digital
   samples* (absolute PCM16 <=16). The first sample in a new audible
   region receives 1/N amplitude; the Nth sample is unchanged.
   This also arms at firmware/model startup. It is explicitly **not**
   triggered on every SSI register write or every phoneme; brief
   gaps within a word or stop-consonant release are left alone.
   The Pico reference filter/ROM source code remains unmodified.
   Edge count is logged to allow A/B.
2. **Conditional idle synthesis skip** after at least **2.5 seconds**
   of exact zero PCM16 output **and** `ssi263_request(chip)` true
   (a model A/R request), with no new SSI register writes.
   The native Pico `ssi263_skip()` function advances internal clock,
   timer and register state without producing sample-by-sample output.
   The MCU still sends exact zero PCM blocks over SPI to keep the
   existing R6 FIFO alive without artificial underruns.
   **This saves FPU CPU work, not SPI bandwidth.**
   Any subsequent Apple SSI write immediately cancels fast idle
   before being applied. If the model continues making nonzero
   low-level hiss, fast idle NEVER engages—this is deliberate
   protection of voiced and unvoiced sounds.
3. **Optional compile-time A/B noise gain:** `SSI263_R7_NOISE_PERCENT`
   defaults to `100` (original native Pico noise). A later
   controlled test may compile `85` or `70` without altering
   the pinned model source. This has **not** been correlated by
   phoneme with the native chip, so default should remain 100.
4. Additional OSD line every ten seconds:

```
P10 R7 E=<edge ramps> IDLE=<skipped blocks> Q=<0|1>
```

The existing `RATE`, `CPU`, `SPI`, `OVR`, `FIFO`, `UND`
and `G` reports are unchanged; the source-rate denominator
remains **22,050 samples/sec**, and initial FIFO timebase is unchanged.

**One boundary this revision does NOT fix:** Explicit SSI
CTL **powerdown** causes a hardware `powered_o` gating of the
hybrid PCM signal to zero at `hdl/mockingboard/ssi263_slot.sv:119`;
the FPGA bridge also immediately resets the FIFO. MCU-side
attack shaping cannot soften a hard powerdown edge.
For an audible click *exactly* coincident with CTL powerdown,
we need a separate, hardware-tested FPGA release envelope
(and careful bus-timing/SSI power semantics checks).
Do not introduce that alongside this MCU-only R7A validation.

## Tunable guardrails

In `boards/a2n20v2-Enhanced/src/a2n20_bl616/firmware_host/ssi263_hybrid.c`:

```c
#define SSI263_R7_ATTACK_US 2500u
#define SSI263_R7_PREQUIET_MS 18u
#define SSI263_R7_PREQUIET_ABS 16u
#define SSI263_R7_IDLE_ZERO_MS 2500u
#define SSI263_R7_NOISE_PERCENT 100u
```

All are `#ifndef` controls. Set `SSI263_R7_ATTACK_US=0u` to
disable edge shaping for controlled before/after comparison.
Setting `SSI263_R7_NOISE_PERCENT` to 85u gives a model noise
source attenuation of approximately -1.41dB, **not** a global
volume change.

## Validation / remaining gaps

CI `.github/workflows/ssi263-p10r7-speech-transitions-idle.yml`
checks:
- PCM16 attack at 44/22/11k, including negative full-scale sample.
- No extra attack on 10ms gaps, attack on 20ms true silence.
- Explicit disable and model power-transition rearm.
- GCC syntax of MCU renderer for source-rate dividers 1, 2, 4.
- Retention of original Enhanced USB/HID and R6 FPGA protocol.

**Not hardware-qualified yet:** actual BL616 SDK cross-compile,
low-latency voice transients, any quality benefit, or the idle
fastpath engaging. If there are few exact-zero samples or
no A/R assertion, `IDLE` correctly stays zero.

## Safe deployment — one PowerShell command per paste

Keep the working R6 clone and FPGA configuration intact:

```powershell
git clone --branch petar/ssi263-p10r7-speech-transitions-idle-20261109 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p10r7
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10r7\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
```

```powershell
make -j4
```

```powershell
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin
```

After successful native BL616 SDK build, preserve a copy of the
working R6 Stage 2 image before changing firmware. Then from the
`a2n20_bl616` parent directory:

```powershell
Set-Location ..
```

```powershell
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

This writes **Stage 2 at `0x40000`**. **Never overwrite the
original Stage 1 at `0x00000`**. A previous readback check did
not locate the compare file, so programmer write success by itself
does not prove readback equality.

## Hardware A/B plan

1. Retain or record the R6 22k optical capture.
2. Flash R7A Stage 2 only; keep the **same R6 FPGA bitstream**.
3. Repeat the identical Mockingboard speech demo, capture optical
   audio, note whether first and last syllables are cleaner.
4. Verify `G=0`, `UND` not growing, `OVR` near zero,
   `RATE` close to 22,050/s and USB TAB still works.
5. Compare `R7 E` (should increment on genuine quiet-to-active
   entries) and `IDLE` (may remain zero if powered model hiss
   never becomes true digital silence). `Q=1` signifies idle
   fastpath active at report time.
6. If attack ramp hurts fricative consonants, rebuild with
   `SSI263_R7_ATTACK_US=0u` to isolate it, before changing
   voice ROM, formant widths or noise excitation.

The R7A MCU cross-build is not asserted passing by GitHub CI.
