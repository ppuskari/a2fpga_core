# P10-R8 — First guarded BL616 DSP hot-path experiment

**Board:** `boards/a2n20v2-Enhanced` only.  
**Branch:** `petar/ssi263-p10r8-voiced-dsp-speed-20261109`.  
**Baseline:** working P10-R7A BL616 + timing-qualified P10-R6 22.05 kHz FPGA.

## Hardware evidence: R7A Demo Disk 1 screenshots

- At boot and while SSI speech is inactive, `B=0`,
  `CPU=0`, `SPI=0`. No idle synth work is being done;
  `R7 IDLE=0 Q=0` is not a bug in this power-off state.
- During the speech demo, attack-shaper count `E` rises
  from 0 to at least **74**, confirming it is active. A high
  count is not proof that every gated transition sounds better:
  compare identical optical captures before retaining the ramp.
- During demanding speech, `CPU` peak **8,780–9,712 us**;
  `SPI` peak **821–1,057 us**; `RATE` around
  **20,565–21,898 /s**; `OVR` per 10s window **174–896**;
  occasional `UND>0`. Source 128-sample block deadline
  is **5,805 us** at 22.05kHz, so audible FIFO starvation
  remains possible.
- `G=0` in the observed intervals: SSI event sequence
  integrity remains good.
- NOTE: `CPU` measures wall-clock time around the full MCU
  synth+PCM processing call, including FreeRTOS preemption;
  it is **not** isolated CPU-cycle consumption. Higher SPI
  peaks may additionally reflect OSD/video redraw contention.

## Suspected expensive instruction in the native Pico model

In `reference/ssi263/pico-v1.0.1/ssi263.c`,
`chip_run()` executes:

```c
if (swell != 0.0 && la[VA] > 0)
    nz = nz * (1.0 + swell * cos(2 * M_PI * c->phase)) / swell_norm;
```

The default model has nonzero `noise_voice_swell`. For
a voiced segment this calls the C library cosine repeatedly
inside the synthesis loop. This is a strong candidate for
RV32 BL616 CPU pressure, although **we have not yet proven
it is the dominant source** relative to oscillator/filter DSP,
phoneme transitions, SPI mutex contention or FreeRTOS
scheduling.

R8 defines `SSI263_R8_FAST_SWELL` **only for the Enhanced
BL616 build's `ssi263.c`**, changing this one invocation
to an instance-local 512-interval precomputed cosine table
with linear interpolation. The 513 float values require
approximately **2052 extra bytes** of model RAM. The table
is generated once during `ssi263_new()`, not repeatedly
during playback.

When compiled **without** `SSI263_R8_FAST_SWELL`, the
unmodified Pico reference math and API are retained.
No ROM data, pitch control, A/R timing, DSP filter
coefficients, noise gain, phoneme sequencing or
speech register reads are modified.

The R7A onset envelope and guarded idle path are unchanged,
as are the R6 FPGA 22k PCM divider, 44.1k HDMI, DOC piano,
AY effects, full IIgs VGC, and original Enhanced USB
keyboard/media-remote input and 8-port hub configuration.

## PCM fidelity test: PASS

GitHub CI compiles both old and R8 Pico C with the
production `-O3 -fsingle-precision-constant` options and
synthesizes the same 49,152 16-bit PCM samples at 22.05kHz
across 12 distinct phoneme data values.

- Waveform correlation: **1.000000000** (rounded to 9 places)
- Signal-to-difference RMS ratio: **99.385 dB**
- Maximum raw PCM sample difference: **1 LSB**
- Both binaries passed C checks; R7A attack regression also passed.

This is mathematical equivalence of a constrained fixture, **not
a direct match to a real SSI-263 chip**. The fixture includes some
full-scale PCM samples, so a natural-speech capture should also
be compared.

An x86/Linux runner measured approximately `0.012` CPU
seconds for each variant: **no measurable x86 performance gain**.
BL616 may behave differently due to its single-precision
hardware and RISC-V libm implementation. Do not promise
performance improvement until actual hardware readings.

## One-line PowerShell commands

Use a fresh clone, leaving your known-good R7A and R6
builds untouched:

```powershell
git clone --branch petar/ssi263-p10r8-voiced-dsp-speed-20261109 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p10r8
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10r8\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
```

```powershell
make -j4
```

```powershell
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin
```

Native BL616 SDK compilation is **not** established by the
Linux host tests. Preserve your working R7 Stage2 .bin for
rollback before experimenting.

If the BL616 build passes, retain the R6 FPGA bitstream
(no FPGA change); navigate to the parent MCU folder:

```powershell
Set-Location ..
```

```powershell
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

This preserves the factory **Stage1 at 0x0** and writes
only **Stage2 at 0x40000**. The programmer previously
couldn't find its verification readback artifact; a
successful write status alone does not prove byte-for-byte
verification.

## Acceptance experiment

Boot diagnostic should include:

```
P10 SOURCE=22050HZ DIV=2
P10 R8: FAST VOICED COS LUT512
```

Replay exactly the same Mockingboard in Concert speech
demo, while noting `CPU`, `SPI`, `OVR`, `FIFO`, `UND`,
`G`, `R7 E` and `IDLE`. R8 deliberately preserves the
same periodic diagnostic log format for direct comparison.

**Decision gate:** Keep the R8 math optimization only if
real BL616 data indicates fewer deadline misses/underruns
without degradation in optical audio quality or USB
responsiveness. If `CPU` still peaks around 9ms,
instrument model subphases and scheduler delays instead of
changing voice timbre to conceal underflow artifacts.

A more aggressive yet separate next optimization could
target `latch_all()` filter coefficient updates or glottal
FIR work—but those require independent audio-parity tests.
