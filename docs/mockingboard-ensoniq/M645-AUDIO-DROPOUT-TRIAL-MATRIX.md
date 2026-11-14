# M6.4.5 — audio-only dropout trial builds (2026-11-14)

## Context
- Enhanced a2n20v2 Apple IIe / Tang Nano 20K, slot 4.
- Known-good `petar/mb-doc-m643-pilot-ab-20261114`: 1002Hz right HDMI pilot can be switched OFF with S2 and musical playback remains clean.
- Failing `petar/mb-doc-m644-clean-no-pilot-20261114`: no pilot logic; full-stereo digital-zero interruptions ~0.976s, at varying musical positions with solid HDMI video.
- Physical STA from both branches passed. M6.4.3 stable has *worse* setup slack than failing M6.4.4. Clock frequency alone is not a proven cause.
- Neither a good run nor a failing run by itself conclusively identifies the cause of an intermittent issue.

## Preserved in every test branch
```systemverilog
parameter bit MB_DOC_FX_AY_BYPASS_ENABLE = 1'b0,
parameter bit MB_DOC_DECLICK_ENABLE = 1'b1,
parameter bit MB_DOC_COHERENT_PUBLISH_ENABLE = 1'b1,
```
The 7-zone piano data, all six DOC piano voices, existing 22.05kHz/11.025kHz SSI263 Stage 2/R11 firmware/WarGames path, FPGA debug video overlay disabled at synthesis, final -2dBFS HDMI limiter, and BL616 binaries are unchanged. Do not reflash BL616. Future M6.5 FX bank development remains separate.

## Matrix
| ID | Branch | Only experimental change |
|---|---|---|
| M6.4.5a | `petar/mb-doc-m645a-strobe-watch-20261114` | Pixel-domain audio sample-tick watchdog |
| M6.4.5b | `petar/mb-doc-m645b-packet-direct-20261114` | Same-clock HDMI PCM packet-buffer capture |
| M6.4.5c | `petar/mb-doc-m645c-upstream-pilot-20261114` | Right-channel diagnostic marker BEFORE audio_out |
| M6.4.5d | `petar/mb-doc-m645d-simple-tick-20261114` | Minimal 44.1kHz sample-tick generator |

## Single-line Windows PowerShell commands

For each separate branch use a **separate** checkout directory, keep last good M6.4.3 bitstream for immediate reflash:

```powershell
git clone --single-branch --branch petar/mb-doc-m645a-strobe-watch-20261114 https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-m645a
```

```powershell
git clone --single-branch --branch petar/mb-doc-m645b-packet-direct-20261114 https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-m645b
```

```powershell
git clone --single-branch --branch petar/mb-doc-m645c-upstream-pilot-20261114 https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-m645c
```

```powershell
git clone --single-branch --branch petar/mb-doc-m645d-simple-tick-20261114 https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-m645d
```

After selecting one branch:

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-m645a
```

(Change only the directory suffix to m645b/m645c/m645d for subsequent trials.)

```powershell
py -3 tools\extract_synthlab_piano.py --download
```

Open `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj` under that checkout in Gowin. Each branch is **RTL/source ready only**. Synthesize, place & route, and validate physical timing locally before FPGA programming. No precompiled Gowin bitstream or signed timing closure is claimed here.

## Suggested at-home order and evidence collection
1. Save the original `M6.4.3` working bitstream, capture waveforms, and timing/PnR reports. Keep `M6.4.4` as a failing reference.
2. Try **A** first: run Sugar Plum at least 4–5 repeats with LED3/LED4 visible, record exact WAV position and LED3 status if a 1s dropout happens. If a fault occurs, press S2 only after noting it. This is a sideband sample-clock watchdog, not a clock fix.
3. Try **B** second: packet handling changed, no pilot. Run 4–5 repeats and watch for absent/present 1s gaps or new artifacts. Capture 44.1k stereo WAV.
4. Try **D** third: alternate strobe generator, no pilot, same run. Compare after passing route timing.
5. Try **C** fourth: before-audio_out marker default ON; run 2–3 repeats. Press S2 to OFF, continue 2–3 repeats, then ON again. Keep a continuous recording. Evaluate whether right marker survives music interruptions.
6. If all branches are clean, this suggests physical placement/synthesis or intermittent sink sensitivity and **does not prove** the original problem fixed. Repeat the failing M6.4.4 bitstream without changing capture cables before concluding.
7. For any failure record exact branch/bitstream, Gowin version and route timing, start/end seconds of full-stereo digital silence, HDMI video state, and any LED/marker status. Compare same section in repeat to separate musical rests.

## Important warning
Do not run two branches into the same Gowin output directory; save unique `impl\pnr\` reports and bitstreams per checkout. Reported post-route setup/hold pass does not prove CDC safety. The HDMI packet picker works on `clk_pixel`; its `clk_audio` input is a **sample enable**, not a separate clock in this design. M6.4.5b changes that same-clock buffering, but it is an experiment and needs real receiver validation.

## Rollback
If audio regresses, restore known-good **M6.4.3 with S2 pilot switched OFF**, no MCU flash. Do not merge any trial into main or start M6.5 sampled FX before diagnosing the audio-only full-stereo gaps.

## This checkout: M6.4.5a

**Pixel-domain audio sample-tick watchdog**

No PCM modification. LED4 toggles every 0.5s with normal 44.1k sample ticks (one blink cycle per second). LED3 is a sticky fault and turns on if there are no audio strobes for >2ms. S2 clears the fault latch. Other 3 LEDs retain their old state indications.

**Interpretation:** If a dropout occurs with LED3 ON: sample tick generator or reset path stopped. If LED3 never lights: strobe continued, so look elsewhere. If no dropout: placement-sensitive, inconclusive.

GitHub Actions workflow: `.github/workflows/mb-doc-m645a.yml`. It runs the M6 baseline, M6.4 de-click, M6.4.1 coherent publication and targeted unit regression. CI is not a substitute for Gowin PnR.
