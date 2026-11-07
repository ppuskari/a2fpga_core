# SynthLAB C3 sustain pitch calibration after slowmo.wav

Branch: `petar/mb-doc-c3-pitch-calibration-20261106`
Parent: `petar/mb-doc-synthlab-c3-sustain-only-20261106` (known 1 KB authentic source, low-pitch recording).

## Observation

On the Apple IIe A2N20V2 Enhanced board, 17.31-second `slowmo.wav` showed a pronounced low-register character. Measured simultaneous partials from the recording include approximately 61.6, 123.1, and 246.3 Hz, plus higher harmonics; these are not necessarily three different notes. The authentic 1024-byte `~Piano C3` table has strong DFT bins 1, 2, 4, and 5, not four identical cycles. Thus setting DOC RES2 to compensate an assumed four-cycle waveform can leave a strong fundamental an octave or two below the intended AY melody.

The real Ensoniq frequency law is: `output_table_repetition_hz = (894886.25/(OSC+2)) * FC / 2^(17+RES)`. This is the frequency of repeating the complete 1024-byte table. **The acoustic pitch is not necessarily equal to the table repetition rate** when the PCM contains multiple cycles and subharmonics. We cannot infer exact concert tuning from the file alone without an AY period reference.

## Minimal reversible experiment

The input PCM and the AY->DOC `FC=93623/max(P,1)` formula are unchanged. The Enhanced `top.sv` exposes only one compile-time parameter:

```systemverilog
parameter logic [2:0] MB_DOC_SUSTAIN_RES = 3'd1,
```

Selecting this knob makes all six voice RTS writes use `WTS=2` (1024 bytes) plus selected `RES` bits:

| Value | DOC RTS | Table loop repetition relative to original RES2 |
| --- | --- | --- |
| `3'd2` | `$12` | 1× (your slow/low existing recording) |
| `3'd1` | `$11` | 2× (+1 octave, branch default) |
| `3'd0` | `$10` | 4× (+2 octaves) |

NB: The values above shift **sample playback speed**, not an independent piano-tuning parameter. The timbre and aliasing also change. They do not solve note retriggering or attack/sustain transitions.

## Windows/Gowin test

Clone into a NEW directory (retain earlier P3 and C3-sustain images):

```powershell
git clone --branch petar/mb-doc-c3-pitch-calibration-20261106 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-c3-pitch
```

Generate locally the authentic Apple sample, same process as the prior sustain branch:

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-c3-pitch; py -3 tools\extract_synthlab_piano.py --download
```

Open `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj` in Gowin, synthesize, check sample ROM and all MB-DOC module retention and timing, then program *FPGA only*. BL616 firmware must be left untouched.

Test at `MB_DOC_SUSTAIN_RES=3'd1` first. If still an octave low, change top.sv to `3'd0` and synthesize/route/program a separately named `.fs`. For a baseline A/B revert this parameter to `3'd2` without altering PCM. The change is *not runtime-selectable*; each value requires recompiling the FPGA.

## Verification limits

Icarus RTL now runs the *same* 256 32-bit sample writes and six voice/envelope/PSG-reset regression at each RES=0,1,2, checking exactly `$10`, `$11`, and `$12`. Separate native YM2149 Verilator bench verifies envelope shapes. Hardware Gowin synthesis/timing and musical pitch have not yet been verified on this branch.

Next major instrument milestone should follow SynthLAB bank's native root tuning metadata and keyboard zones, then add a real one-shot attack and original sustain loop with AY note-trigger detection.
