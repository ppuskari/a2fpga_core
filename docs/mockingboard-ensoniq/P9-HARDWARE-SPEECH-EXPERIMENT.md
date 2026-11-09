# P9 — experimental SSI-263 whole-chip, speech-enabled Tang Nano 20K

Branch: `petar/ssi263-p9-hardware-speech-20261109`
Base: `petar/ssi263-p8b-dsp-validation-20261109`
Target: a2n20v2-Enhanced, Apple IIe slot 4; unchanged P6 DOC piano/AY FX.

**Experimental hardware listening candidate. NOT golden SSI263 fidelity.**

## Why P9 exists

P8 created full-chip registers + five stages but delivered almost pure
static and polluted the piano's shared mixer. Hardware test proved
`MB_SPEECH_GAIN_NUM=0` restored the piano without other code changes.

P8B isolated speech while measuring native pinned Pico C against FPGA
PCM on common XCK register traces. P9 improves the actual synthesizer
and *intentionally enables speech for hardware listening*.

## P9 source differences

- Digital controller: independent SSI-263 R0-R4, CTL, XCK, R4-derived
  switched-capacitor filter clock, A/R and VIA CA1 integration.
- Three die-programmable formants F1/F2/F3 plus fixed F4/F5,
  sequentially evaluated over five logic cycles per filter sample.
- NAS changes F2 bandwidth through 256 coefficient ROM settings.
- Six Q12 phoneme controls and speech-rate/articulation-dependent
  transitions; R1 mode 3 pitch glides, mode 1/2 immediate.
- 36-tick glottal kernel from the MIT Pico C reference.
- Correct 15-bit, two-tap noise LFSR, normalized two-pole band-pass at
  0.28*fc and bw 0.15*fc. Separate evolving F2 and F5 FA/noise
  injection weights selected by die ROM b02.
- New stop closure envelope, speech-rate-relative delay/release
  window, early A/R request and CPU-write queue until original stop
  completion. Closure applies to volume **after** five stages.
- R3 output volume now applied *after* HP/filter, preserving the
  acoustic resonator state when amplitude changes.
- 44.1 kHz output from physical logic-rate sample-and-hold area
  integration at 4x host sample rate, followed by a **193-tap**
  single-multiplier time-multiplexed Hamming FIR matching the upstream
  Pico 20kHz / 176.4kHz coefficients in quantized Q15 form.
- Exposes the older 5-tap P8B reconstruction as a compile-time fallback.

### Safety and volume

`boards/a2n20v2-Enhanced/hdl/top.sv`:
```systemverilog
parameter bit MOCKINGBOARD_SSI263_FULL_CHIP_ENABLE = 1'b1,
parameter integer MB_SPEECH_GAIN_NUM = 1,
```

P9's voice is **enabled** in HDMI, speech gain is 1× (not P6's 3×).
The DOC piano synthesis/volume and AY FX sources are unchanged.
A failed render can still distort music while audible because both
signals share the final stereo mix.

To build the **music-isolated** diagnostic fallback, change only:
```systemverilog
parameter integer MB_SPEECH_GAIN_NUM = 0,
```

No MCU firmware update. Keep the last working P6 bitstream available.

## Independent validation

- `.github/workflows/ssi263-p9-hardware-speech.yml` generates/
  verifies 64 phoneme, 50 original formant, 64 glottal, 256 F2/NAS,
  193 FIR coefficient ROMs
- Compiles upstream MIT Pico model and synthesizable P9 RTL
- Compares identical 1MHz XCK register sequences rendered to PCM
- Exercises voiced-only, noise-only and both-off cases
- Tests early A/R, stop closure and pending CPU writes
- Asserts unchanged seven-sample DOC piano configuration
- Verilator lint; does NOT perform Gowin P&R/timing or real-hardware
  audio validation

The pinned C code is not the physical SSI263 silicon itself, and
real recordings from https://www.youtube.com/watch?v=Gciw3PYCVok
are the additional acoustic benchmark.

**Known deviations:** 15-bit ROM decoded parameters are rounded,
fractional glottal pulse placement is approximate, and early A/R
pending-write semantics/timing need more real-hardware corroboration.
Filter-band spectra and waveform correlation remain below strict
C-reference parity; P9 is a listening test, not an assertion of
faithful recreation.

## PowerShell 5.1 (paste one command at a time)

```powershell
git clone --branch petar/ssi263-p9-hardware-speech-20261109 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p9
```
```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p9
```
```powershell
py -3 tools\extract_synthlab_piano.py --download
```
```powershell
py -3 tools\generate_ssi263_voice.py
```
```powershell
py -3 tools\generate_ssi263_p8_roms.py --check
```
```powershell
py -3 tools\generate_ssi263_p9_nas_rom.py --check
```
```powershell
py -3 tools\generate_ssi263_p9_output_fir.py --check
```
```powershell
Start-Process .\boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj
```

Gowin synthesis, place/route, timing analysis and bitstream. Check
resource counts and WNS: the serial FIR requires a valid 54MHz path
and its FIFO/ROM clocks to synthesize as expected. No known hardware
timing closure for P9 yet. Preserve P6 rollback.

### First hardware experiment

1. Virtual piano keyboard alone; should sound identical to P6.
2. Demo Disk 1 opening music and explosions; check missing notes.
3. `RUN S/ONLY` → `A MESSAGE`; speech should be audible with
   distinct vowels vs burst noise. Stop if it is all static.
4. Record same native demo phrase at 44.1k WAV, unprocessed, and
   note P9 volume, clipping, articulation and CA1 progress/hangs.
5. Optional piano while speaking to check mixing headroom.

If piano regresses, switch only `MB_SPEECH_GAIN_NUM` back to 0,
rebuild, and confirm sound returns. Do not tune the DOC piano to
compensate for defective SSI voice.
