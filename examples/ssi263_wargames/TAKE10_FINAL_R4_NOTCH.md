# Take 10 — Subtle last-notch vocal darkening, native SSI-263 only

**Listening reference:** The preferred and user-qualified Take 9 is `r4e5_k2kv1`, using R4=$E5, K (two frames) + KV (one frame) for the initial consonant in GAME. The user found the synthesized GAME still a little bright compared with the movie, but had previously considered R4=$E4 too dark for the whole sentence.

These Take 10 comparisons retain the **exact same R0 phonemes, R1 fundamental pitches, R2 durations, R3 articulation and volume, and 1.02MHz master clock** as the preferred Take 9. They only vary the original SSI-263 **R4 filter-frequency control** by one register step. There is NO post-processing, new DSP, sample playback, altered chip ROM, FPGA/BL616 modification or reflash.

At the existing native clock:
- R4=$E5 corresponds to 1,020,000 / (2*(256-229)) = **18,888.9 Hz** filter clock.
- R4=$E4 corresponds to 1,020,000 / (2*(256-228)) = **18,214.3 Hz** filter clock.
- Thus the whole filter clock is lowered only **3.57%**. This is **not a direct change to the vocal fundamental** or an assurance that the movie/synthesis spectral centroids will converge by 3.57%.

## Three-way comparison

| Listening label | Native chip control | WAV | Apple II executable |
|---|---|---|---|
| Take 9 (reference) | R4=$E5 throughout | `wargames_ssi263_r4e5_k2kv1.wav` | `wargames_r4e5_k2kv1.raw` |
| Take 10A (whole phrase) | R4=$E4 throughout | `wargames_ssi263_r4e4_k2kv1.wav` | `wargames_r4e4_k2kv1.raw` |
| **Take 10B (preferred experiment)** | R4=$E5 through SHALL/WE/PLAY/A, **switch to $E4 in the PA before GAME** | `wargames_ssi263_r4e5_gamee4_k2kv1.wav` | `wargames_r4e5_gamee4_k2kv1.raw` |

**Reason for Take 10B:** It darkens only the word the listener identified as overly bright while preserving the established first four words sample-for-sample in the native C model. It writes `R4=$E4` at the same R0 event index 12 where Take9 already sets R1 for GAME (start of the PA after the standalone A), so the R4 transition precedes the native K/KV hard G onset without changing any phoneme duration. This is a physical SSI-263 register command, not an effect.

## Important locked baseline

- **K2+KV1 hard G unchanged:** ROM K `$29` for 2 frames (`$A9`), then ROM KV `$26` for 1 frame (`$E6`) followed by AY `$05` for 4 frames and M `$37` for 4 frames.
- Exactly **18 R0 records, 45 SSI frames**, about **2.191 seconds**. Movie reference is about 2.194s.
- The standalone A still uses AY `$45`, not AH.
- All R1 inflection changes are retained exactly: initial `$1B`, then `$53`, `$3B`, `$63`, `$53`, `$83`.
- R2=`$48` and R3=`$68` remain fixed.
- The unchanged SPI idle suspension and FPGA/MCU remain the R11 known-good baseline; no firmware rebuild or flash needed.

## Getting the actual WAVs on Windows

Source sync, one PowerShell command:
```powershell
git -C C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11 pull --ff-only
```

Create artifact folder:
```powershell
New-Item -ItemType Directory -Force -Path C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11\artifacts\wargames_take10 | Out-Null
```

Open the GitHub Actions workflow **SSI263 WarGames Take10 native one-notch voice** for the latest passing run; the artifact name is `wargames-take10-final-notch-native-ssi`.

Then use:
```powershell
gh run download RUN_ID -R ppuskari/a2fpga_core -n wargames-take10-final-notch-native-ssi -D C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11\artifacts\wargames_take10
```

Replace `RUN_ID` with the successful run number from GitHub. (We will also provide it directly with the result.) The artifact contains all three labeled WAVs and all three `.raw` executables. As before, import each `.raw` as an Apple II binary at **$6000**, then `CALL 24576`.

**Comparison order:** preferred Take9 → Take10B (GAME only) → Take10A (all words). This is a listening/ear judgment for overall timbre, not yet a proven objective match to the film.
