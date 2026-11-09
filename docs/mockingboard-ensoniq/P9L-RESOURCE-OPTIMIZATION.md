# P9L — Tang Nano 20K resource reduction

Baseline: P9 experimental hardware speech, with DOC piano and AY FX intact.

## Hardware synthesis report (user's Gowin run)

Gowin RP0006: 23,140 logic units vs 20,736 allowed.
Breakdown: 15,294 LUTs, 7,492 ALUs, 24 ROM16s, 55 SSRAMs.
Shortfall: 2,404 units (11.6% over capacity).

This is a **logic mapping** limit, not a syntax or timing result.
No proof yet that the optimized version fits; run Gowin synthesis.

## RTL changes

`hdl/mockingboard/ssi263_p8_chip.sv`:
- Replaced **signed divided by 15** in glottal excitation with
  Q15 reciprocal `2185 >> 15` (relative gain deviation ~0.021%).
- Replaced **signed 64-bit divide by 491520** in fricative source with
  `839 >> 20` Q20 reciprocal (deviation <0.08%).
- Merged R3 volume and stop-closure control into a **12-bit Q12**
  multiplier. Applies after vocal tract and HP, no wide divider.
- Output scale remains the original 6x P9 chip gain.
- Preserved all 64 phonemes, six parameter transitions, five stages,
  256 NAS-dependent F2 coefficients, 193-tap serial reconstruction,
  early A/R and right VIA CA1, piano and FX.
- Preserved `MOCKINGBOARD_SSI263_FULL_CHIP_ENABLE=1` and
  `MB_SPEECH_GAIN_NUM=1`. This is still an *audible experimental*
  build. Change the latter to 0 for music isolation.

## Testing

`.github/workflows/ssi263-p9l-resource-optimization.yml`
runs isolated voice, noise, silence, early A/R and full 50 kHz
C-vs-RTL diagnostic comparisons. Quantized arithmetic will introduce
small systematic differences, which must be measured before hardware
audio acceptance. Do not claim exact C waveform parity.

GitHub Actions P9L isolated regressions **passed** (run 42626494600):
P9L peak -2.88 dBFS, RMS -17.55 dBFS, 0% clipping,
correlation 0.5975 vs P9 0.598; acoustic behavior is effectively unchanged
within the current short test sequence. Strict C-model fidelity does NOT pass.

Gowin P&R and timing **have not been verified**. Only the user-side
Gowin mapper can confirm the new resource count.

## Single-line PowerShell 5.1

```powershell
git clone --branch petar/ssi263-p9l-resource-opt-20261109 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p9l
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p9l
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

Check the **RP0006 logic count** on synthesis before P&R.
If count is close to 20,736, inspect resource reserves and timing.
Do not program if either synthesis or P&R fails.
