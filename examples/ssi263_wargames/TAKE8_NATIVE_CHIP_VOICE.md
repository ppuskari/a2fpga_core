# Take 8: darker Joshua voice using **only original SSI-263 registers**

**Branch:** `petar/ssi263-p10r11-spi-suspend-wargames-20261111`  
**Parent demo:** Take 7 `wargames_slot4_film_pitch.s` / `render_wargames_film_pitch.c`.  
**Hardware:** Apple IIe, Enhanced Mockingboard slot 4, native SSI-263 interface; run executable at `$6000` using `CALL 24576`.

The user requested a deeper, more convincing Joshua/WOPR voice **without any DSP, PCM resampling/postprocessing, new phoneme ROM, added effects, changes to the FPGA synthesizer, or changes to the BL616 firmware**.

The 1980s SSI-263A manufacturer datasheet itself recommends changing **Filter Frequency (R4, FF7..FF0)** to alter voice type (bass, baritone, etc.) and explicitly says these bits do **not** affect the excitation/inflection pitch:
https://downloads.reactivemicro.com/Electronics/Speech/SSI-263A%20Data%20Sheet%20v2.pdf

## Controlled R4 sweep

All recordings use the exact Take 7 17-record, 45-frame R0 score (2.1914 seconds), the same wordwise R1 pitch movement, and the same clean "AY" word for standalone "A". The changed setting is written by Apple 6502 using `STA $C444` (SSI R4), **exactly as original hardware permits**.

R4 controls the clock of the switched-capacitor vocal tract filters:

`filter_clock_hz = 1,020,000 / (2 * (256 - R4))`

| Preview | R4 | R3 | Filter clock | Character to evaluate |
|---|---|---|---|---|
| `film_pitch` | `$E8` | `$68` | 21,250Hz | Baseline Take 7 |
| `r4e4` | `$E4` | `$68` | 18,214Hz | Mild/medium darkening |
| `r4e0` | `$E0` | `$68` | 15,937.5Hz | Deeper native voice |
| `r4de` | `$DE` | `$68` | 15,000Hz | 0.706× filter clock: **exactly ~six semitones lower** than Take 7's filter clock |
| `r4e0_t7` | `$E0` | `$78` | 15,937.5Hz | Same filter response, native **T7** articulation instead of T6 |

**Key distinction:** These are shifts in vocal-tract **filter clock**, not direct pitch shifts of the glottal frequency. The fundamental F0 should remain controlled by R1/R2. The actual perceived timbre may change non-linearly, and the lowest R4 can reduce intelligibility; listening is decisive.

Articulation register R3 high nibble (CTL/T2..T0) selects the native phoneme-to-phoneme transition speed; the low nibble (A3..A0) is output level. Both versions `$68` and `$78` use amplitude 8 and stay powered on; `$78` uses faster articulation rate 7, which may emphasize the requested sharper, staccato sound without introducing any PCM envelope.

All programs send `R3=$80` power-off before returning to Applesoft.

## CI evidence

The dedicated workflow `.github/workflows/ssi263-wargames-take8-native-voice.yml` builds **all five** Apple II 6502 binaries and all five carrierless Pico SSI C-model 22,050Hz 16-bit WAVs. It verifies:
- byte-identical 17 SSI R0 phonemes and native R1 control schedule across all variants (same 45 frames)
- the only changed SSI registers are R4, and R3 for the T7 experiment
- 2.1914s length, PCM headroom, correct file formats and distinct waveform digests
- existing R11 FPGA/BL616 source files **unchanged**; no firmware or bitstream rebuild/flash needed

The initial CI pass succeeded: 5/5 previews valid, **no clips**, all variants have distinct generated output. The peak PCM16 magnitudes were 23,331 (baseline), 27,394 (E4), 23,376 (E0), 23,207 (DE), 24,481 (E0 T7).

**Workflow build page:** https://github.com/ppuskari/a2fpga_core/actions/workflows/ssi263-wargames-take8-native-voice.yml

## Where to get WAVs and Apple II programs on Windows

Sync your existing checkout (**one PowerShell command per line**):

```powershell
git -C C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11 pull --ff-only
```

The source is under:

```text
C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11\examples\ssi263_wargames\
```

To download the actual generated files, use GitHub CLI (`gh`) rather than `git pull`:

```powershell
New-Item -ItemType Directory -Force -Path C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11\artifacts\wargames_take8 | Out-Null
```

```powershell
gh run download 43321005861 -R ppuskari/a2fpga_core -n wargames-take8-native-ssi-only -D C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11\artifacts\wargames_take8
```

```powershell
explorer C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11\artifacts\wargames_take8
```

The artifact contains ten files, with filenames:
- `wargames_ssi263_film_pitch.wav`, `wargames_film_pitch.raw`
- `wargames_ssi263_r4e4.wav`, `wargames_r4e4.raw`
- `wargames_ssi263_r4e0.wav`, `wargames_r4e0.raw`
- `wargames_ssi263_r4de.wav`, `wargames_r4de.raw`
- `wargames_ssi263_r4e0_t7.wav`, `wargames_r4e0_t7.raw`

For Apple II DOS3.3/ProDOS disk image import, treat each `.raw` as an executable load-address `$6000` BIN file, then `CALL 24576`. Do not add a duplicate DOS3.3 binary header when the disk editor already creates one.

**Suggested listening order:** baseline E8 → E4 → E0 → DE. If E0 sounds closest but the consonants still blur, compare E0 versus E0+T7 to isolate the chip's native articulation rate. No need to flash either FPGA or MCU, and the original Take 7 source and binaries are preserved.

This is a controlled SSI-263-native voice experiment, not yet a measured acoustic or listener-confirmed match to the copyrighted film performance.
