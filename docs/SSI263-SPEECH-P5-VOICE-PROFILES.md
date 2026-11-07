# SSI-263 Speech P5 — selectable FPGA voice quality profile

Derived from hardware-proven speech P4 bus correction. Does NOT merge with
the separate Mockingboard-to-DOC piano P4 branch.

## Profiles (compile-time parameter, not yet runtime menu)

Set `MOCKINGBOARD_SSI263_VOICE_PROFILE` in
`boards/a2n20v2-Enhanced/hdl/top.sv`:

- `0`: the original P4 voice path, same PCM scaling, LFSR contribution,
  abrupt phoneme boundaries; A/B control.
- `1` (default): approximately +6 dB gain, saturating 16-bit limiter,
  gentler noisy-consonant LFSR level, and 4-sample one-pole step smoothing
  at the 16 kHz speech sample tick. Explicit pause phonemes decay to zero.
  Immediate power-off still forces zero PCM.

The SSI CPU registers, P4 corrected data-valid write strobe, phoneme
sequencing and right-VIA CA1 connection are unchanged. This is *not*
a new recorded-speech library or authentic SSI-263 model yet. The
configuration seam lets future renderers use the same five-register
Mockingboard command stream and swap the source with a formant model
or licensed/user-provided phoneme assets.

IMPORTANT: profile selection currently requires synthesizing a separate
FPGA bitstream. A user-configurable runtime menu or EEPROM setting is
a future task and must not be implied by the compile-time parameter.

## Windows PowerShell 5.1: one-line-at-a-time

```powershell
git clone --branch petar/mb-ssi263-speech-p5-voice-profiles-20261107 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-speech-p5
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-speech-p5
```

```powershell
py -3 tools\generate_ssi263_voice.py
```

```powershell
(Get-Content .\boards\a2n20v2-Enhanced\hdl\ssi263_voice.mem | Measure-Object -Line).Lines
```

Expected 8192. Open
`boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj` in Gowin,
run synthesis / place-and-route, check timing and produce the bitstream.
**FPGA ONLY; keep BL616 MCU firmware as-is.**

Boot the original Mockingboard Demo Disk 1 to speech option A.
Record the same line at the same output/recording gain as P4.
Compare voice RMS/peak, high-frequency static between words,
consonant intelligibility and whether any phrase truncates.
If the enhanced voice is distorted, lower the gain or adjust the
filter rather than changing the already-fixed SSI bus timings.

No claim of actual Gowin synthesis, hardware testing, audio quality
or measured decibels is made by this source-level update.
