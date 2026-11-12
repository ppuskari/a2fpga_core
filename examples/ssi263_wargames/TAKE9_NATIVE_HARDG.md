# WarGames Take 9 — R4 voice midpoint plus authentic hard /g/ articulation

This experiment uses **only the SSI-263's original ROM phonemes and control registers**. No DSP pitch shifting, PCM edits, altered phoneme library, FPGA or BL616 firmware changes, or extra voice processing.

## Listener feedback behind the experiment

- The Take 8 **R4=$E4** rendition is noticeably closer in depth, but sounds *just slightly lower* than desired.
- **R4=$E0** and **$DE** are too low/dark.
- The word **GAME** has an almost missing, overly smooth/rounded **G** onset.
- Keep Take 7's authentic movie-derived R1 pitch contour, correctly spoken standalone A=AY, the 96ms word boundaries, and the total duration.

## Why the original G was soft

The pinned physical SSI-263 ROM in `reference/ssi263/pico-v1.0.1/rom_bits.csv` contains two different velar allophones:

- **KV**, ROM `$26`: the voiced velar-like component. Its ROM **b00=1**, which tells our pinned Pico C model to *clear* the stop closure.
- **K**, ROM `$29`: the hard velar stop. Its ROM **b00=0**, which engages the model's original closure/release path.

The previous phrase used only `KV` (R0 byte `$66`, three frames), making the transition to vowel AY excessively rounded. Take 9 tests **K followed by KV** within the **same three frames** already allocated to the first consonant in GAME. This is a native SSI allophone sequence, not added noise or PCM shaping. It may produce a hard /k/ rather than a realistic voiced /g/ depending on the ear, so evaluate both durations.

## Controlled variants

At the 1.02MHz clock, SSI filter frequency is `1,020,000 / (2*(256-R4))` Hz. This changes vocal-tract filter resonance, not SSI fundamental frequency (which remains R1 controlled).

| Variant | R4 | Filter clock | GAME's initial R0 bytes | Intended difference |
|---|---|---:|---|---|
| `r4e5` | `$E5` | 18,888.9Hz | `$66` = KV 3 frames | Slightly brighter than E4, original soft G |
| `r4e5_k1kv2` | `$E5` | 18,888.9Hz | `$E9,$A6` = K 1 frame + KV 2 frames | **First listening recommendation** |
| `r4e5_k2kv1` | `$E5` | 18,888.9Hz | `$A9,$E6` = K 2 frames + KV 1 frame | More emphatic closure |
| `r4e6_k1kv2` | `$E6` | 19,615.4Hz | `$E9,$A6` | Slightly brighter than E5 with same G attack |

E4's filter clock is ~18,214.3Hz and the original E8 is 21,250Hz. E5 is **one register step** brighter than E4 (the user's requested "tad" upward); E6 is the register-space midpoint between E4 and E8. Neither changes R1 F0 or the actual movie pitch trajectory.

All four:
- Use Take 7/8's exact original 45 frames and word-start indices: first 13 R0 records produce groups at frames 0, 12, 19, 27, 32. The GAME phoneme schedule remains K(+KV) **3**, AY **4**, M **4**, final PA **2** frames.
- Preserve R1 writes `$1B,$53,$3B,$63,$53,$83` at identical event indices 0/2/4/6/9/12.
- Keep `R2=$48`, `R3=$68` (T6, amplitude 8), all previous word vowels and the standalone **AY** pronunciation of the article "A."
- Send explicit `R3=$80` power-off at completion, using the real right-VIA A/R flag.
- Compile to 6502 Apple IIe slot-4 binary at $6000 and render an independent carrierless native Pico SSI model WAV at 22.05kHz.
- Do **not** change R11 PCM suspend/resume. Hardware audio and BL616 code stay untouched.

## CI results

Dedicated workflow `.github/workflows/ssi263-wargames-take9-native-hardg.yml` is green on run:
https://github.com/ppuskari/a2fpga_core/actions/runs/43322912301

- All four 6502 files assembled/linked.
- 17-record soft-G control; 18-record K+KV variants; matching R0 bytes in the Apple executable and native C source.
- Explicit ROM check verified **K b00=0** and **KV b00=1** in the pinned physical ROM.
- All maintain **45 frames**, 2.1914s duration, the same positions of the five words, no clipping, and distinct PCM digests.
- Not yet hardware-listened or optically compared; **a different PCM hash is not evidence of a perceptually stronger G.**

The action creates artifact `wargames-take9-r4e5-hardg`, containing 4 WAVs and 4 .raw Apple IIe programs.

## Windows: sync sources and retrieve WAV / RAW artifacts

Each command below is an independent **single PowerShell line**.

```powershell
git -C C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11 pull --ff-only
```

```powershell
New-Item -ItemType Directory -Force -Path C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11\artifacts\wargames_take9 | Out-Null
```

```powershell
gh run download 43322912301 -R ppuskari/a2fpga_core -n wargames-take9-r4e5-hardg -D C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11\artifacts\wargames_take9
```

```powershell
explorer C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11\artifacts\wargames_take9
```

Files:

- `wargames_ssi263_r4e5.wav` + `wargames_r4e5.raw`
- `wargames_ssi263_r4e5_k1kv2.wav` + `wargames_r4e5_k1kv2.raw`
- `wargames_ssi263_r4e5_k2kv1.wav` + `wargames_r4e5_k2kv1.raw`
- `wargames_ssi263_r4e6_k1kv2.wav` + `wargames_r4e6_k1kv2.raw`

Import .raw binaries into an Apple II disk image with BIN load address **$6000**. Then use `CALL 24576`. No FPGA or MCU reflash.

**Suggested listening order:** E5 soft G (control) → E5 K1/KV2 → E5 K2/KV1 → E6 K1/KV2. The K part needs an audible closure and burst, but avoid producing “KAME” with an overly strong unvoiced consonant; the final judge should be the user's listening and, if desired, an optical comparison to the movie.
