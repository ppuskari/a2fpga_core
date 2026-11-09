# P7-R1: Recovered SSI-263 phoneme parameter FPGA formant core

**Branch:** `petar/mb-doc-p7-ssi263-die-formant-r1-20261108`

**Base:** `petar/mb-doc-p6-speech-level-calibration-20261107`

**This is an EXPERIMENTAL AUDIO ENGINE, not a new golden baseline.**

## Why the architecture changed

The preceding P4/P5 renderer plays 128 repeating waveform samples
per phoneme, plus simple LFSR noise. It can speak, but does not reproduce
the changing analog vocal-tract resonances, fricative filtering and
articulation of the silicon SSI-263.

The supplied native hardware reference `ssinativespeech.wav`
(https://www.youtube.com/watch?v=Gciw3PYCVok) was measured from
its captured audio as 44.1 kHz stereo, duration 109.3004 s,
peak about -3.00 dBFS, total RMS about -29.68 dBFS
(including silence). It is the authentic reference target.
Earlier experimental recordings: `voice1.wav` -12.89 dBFS peak,
`voice2.wav` -11.31 dBFS peak. These are not necessarily
sample-aligned or gain-matched content, so do not claim a numeric
speech-quality improvement from those measurements alone.

## Synthesis implementation in this first revision

Profile **2** is now the default, selectable with
`MOCKINGBOARD_SSI263_VOICE_PROFILE` in Enhanced `hdl/top.sv`.
Profiles 0 (raw P4 sample playback) and 1 (enhanced P5 PCM)
remain accessible at **compile time** for A/B comparison.

The new audio-only `hdl/mockingboard/ssi263_die_formant_voice.sv`:

- consumes **64 decoded phoneme parameter sets** obtained from
  actual SSI-263P silicon imaging and published by Tamas Geczy,
  via `kue-m/mockingboard-pico` (MIT);
- `tools/generate_ssi263_die_formants.py` derives 64 x 128-bit
  coefficient words into
  `boards/a2n20v2-Enhanced/hdl/ssi263_die_formants.mem`.
  Coefficient ROM is COMMITTED; it can be regenerated offline;
- uses the upstream capacitor-law frequency mapping for the three
  physical die-coded formant settings (F1/F2/F3);
- uses three parallel **fixed-point damped IIR resonators**,
  a simple original two-stage glottal pulse, dynamically clocked
  LFSR highpass noise, die-coded voiced and fricative amplitude,
  elementary closure gating, NAS attenuation and output smoothing;
- runs at 16 kHz PCM, synchronized to the existing 54 MHz logic
  clock; feeds the *existing* 16-bit speech mixer.

### Fidelity limits — intentionally explicit

This is not a bit-exact hardware SSI-263 and not a complete port
of the floating-point C engine. Filter clock scaling, analog
switched-capacitor topology, F4/F5, detailed pole bandwidth, real
glottal excitation, inflection law, phoneme-to-phoneme parameter
glides and closing/release timing need additional work. Coefficients
are generated using a fixed nominal 19 kHz filter rate and
experimental damping factors. Current approximations may sound
different from the native recording and may need significant tuning.
DSP cell utilization and Gowin timing are still to be checked.

Crucially **the SSI CPU register path, fixed bus-data capture strobe,
SSI A/R timer, right VIA CA1, AY-to-DOC bridge, seven piano
samples, native AY FX, and calibrated music HDMI gain were NOT
changed.** The P6 `MB_SPEECH_GAIN_NUM=3` path remains active.
If P7 voice is overdriven, test that coefficient at 1 or 2 first.

## References and licenses

- https://github.com/kue-m/mockingboard-pico
- https://github.com/lprazdnik/ssi263-speech
- https://www.visual6502.org/images/pages/Silicon_Systems_SSI_263P_die_shots.html
- `third_party/ssi263_die/LICENSE` and `NOTICE.txt`.
  Recovered data and decoded settings are MIT attributed.
- **No MAME SC-01 glottal waveform or firmware has been imported.**

## Windows PowerShell 5.1 (each line separately)

```powershell
git clone --branch petar/mb-doc-p7-ssi263-die-formant-r1-20261108 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-speech-p7
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-speech-p7
```

```powershell
py -3 tools\extract_synthlab_piano.py --download
```

```powershell
py -3 tools\generate_ssi263_voice.py
```

```powershell
py -3 tools\generate_ssi263_die_formants.py
```

```powershell
(Get-Content .\boards\a2n20v2-Enhanced\hdl\piano_multisustain.mem | Measure-Object -Line).Lines
```

Expect **1408** piano ROM words.

```powershell
(Get-Content .\boards\a2n20v2-Enhanced\hdl\ssi263_voice.mem | Measure-Object -Line).Lines
```

Expect **8192** legacy waveform ROM entries.

```powershell
(Get-Content .\boards\a2n20v2-Enhanced\hdl\ssi263_die_formants.mem | Measure-Object -Line).Lines
```

Expect **64** die-derived coefficient words.

```powershell
Start-Process .\boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj
```

Run Gowin synthesis, P&R, and **check DSP usage and timing**
before bitstream programming. **FPGA ONLY, no BL616 firmware flash.**
Do not overwrite previously working P6 bitstreams.

## Hardware acceptance

1. Boot demo disk and confirm the opening AY explosions and DOC music
   do not regress. Compare against P6 for missing notes/piano level.
2. `RUN S/ONLY`, select `A MESSAGE`: listen for uninterrupted
   phoneme progression and no stalled right VIA CA1 IRQ.
3. Record the **same sentence** from real SSI-263 and P7
   at the same analog recording gain, preferably 44.1 kHz stereo WAV.
4. Compare audible articulation (especially vowel /A/, /I/, /ER/,
   S/T/K/P, glottal/stop closures), pitch, hiss during silence,
   mean/peak, and HDMI limiter activity.
5. If P7 fails or sounds worse, rebuild with profile **1**
   rather than changing the stable speech register controller.

## CI

`.github/workflows/mb-ssi263-die-p7.yml` checks ROM regeneration,
isolated P7 renderer simulation, P6 SSI timing regressions and lint.
This does not replace Gowin resource/timing analysis or real hardware.
