# Combined Mockingboard DOC P6 — Speech level calibration

Parent: `petar/mb-doc-p5-speech-p5-combined-20261107`

## Why

Hardware P5 speech recording `voice2.wav` (44.1 kHz stereo, 37.47s)
measured peak -11.31 dBFS, full-recording RMS -26.65 dBFS.
The user wants a speech peak near -2 dBFS while keeping the tested
music playback unchanged. The gap is approximately +9.3 dB, or 2.92x.

## Change

In `boards/a2n20v2-Enhanced/hdl/top.sv`:

`MB_SPEECH_GAIN_NUM = 3` (default)

- Multiply SSI-263 speech PCM by 3 in signed 32-bit arithmetic.
- Keep the 1/8 pre-attenuation in `AUDIO_MODE_MB_DOC` to compensate
  for the music foundation's *existing* 8x HDMI gain stage.
- Limit the 16-bit speech insert and final 17-bit mixed stereo output.
- Preserve the music source selector, AY FX/DC blocking, 7-zone DOC
  piano rendering, music HDMI output gain and limiter exactly as P5.
- Preserve the hardware-proven SSI command protocol and right VIA
  CA1 IRQ path. No ROM, timbre or word-articulation changes in P6.

This is a **calibration experiment**, not a promise of exactly -2 dBFS
on hardware: actual downstream filtering, HDMI gain limiting,
simultaneous music and recording settings all influence final peaks.
A ×3 increase may produce higher clipping frequency during mixed
music/speech; watch the existing one-second HDMI clipping indicator.
If the recording exceeds the intended ceiling or sounds strained,
reduce `MB_SPEECH_GAIN_NUM` to 2 and rebuild.

## Build — one PowerShell command per paste

```powershell
git clone --branch petar/mb-doc-p6-speech-level-calibration-20261107 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-speech-p6
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-speech-p6
```

```powershell
py -3 tools\extract_synthlab_piano.py --download
```

```powershell
py -3 tools\generate_ssi263_voice.py
```

```powershell
(Get-Content .\boards\a2n20v2-Enhanced\hdl\piano_multisustain.mem | Measure-Object -Line).Lines
```

Expected 1408.

```powershell
(Get-Content .\boards\a2n20v2-Enhanced\hdl\ssi263_voice.mem | Measure-Object -Line).Lines
```

Expected 8192.

```powershell
Start-Process .\boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj
```

Run Gowin synthesis/P&R/timing and program FPGA only.

## Hardware validation

1. Repeat the exact Demo Disk 1 speech selection with identical
   capture settings. Expect roughly a 9.5 dB speech-level increase
   *before any limiting*. Verify recorded peak and RMS.
2. Repeat the opening music and explosions. Volume and notes should
   be unchanged versus combined P5.
3. Observe the HDMI clipping-history indicator, including scenes
   with any simultaneous voice and music.
4. Compare consonant clicks, background static, and intelligibility
   separately. P6 does not correct phoneme authenticity.

Current synthesized speech remains original approximate waveforms,
not a speech-library upgrade. Never label P6 golden without real
hardware tests.
