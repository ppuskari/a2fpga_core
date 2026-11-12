# Take 7: pitch from directly analyzed movie voice

**Input for analysis:** User-uploaded `shallweplayagame(1).wav`, 44,100 Hz, stereo, 96,768 frames (2.1942857 s). Only numerical observations are published; the movie recording itself is **not included** in the repository or build artifacts.

This corrects previous assumptions that the final word must reach ~180 Hz. On direct reanalysis the **voiced body of "game" is approximately 128 Hz**, declining toward 120 Hz near release. The earlier 180 Hz estimate is not a dependable measure of this word's dominant fundamental; the processed film voice has strong harmonics.

## Method and observations

- Average stereo channels (L/R correlation ~0.9945). Run YIN/pitch-period analysis on mono resampled to 11,025 Hz, with a 2048-sample analysis window, 128-sample hop, and restricted voiced-frequency range 55–190 Hz; inspect spectral harmonics and time windows separately.
- Reject low-energy unvoiced portions (in particular the latter half of "we" where autocorrelation algorithms often lock onto harmonics). A point estimate from an unvoiced consonant is **not** the actor's glottal fundamental.
- Word ranges are derived from low-energy valleys in the uploaded clip; total 2.194s. They are approximate because the film mix contains background audio.

| Word | Time window analyzed | Fundamental, Hz | Notes |
|---|---|---|---|
| SHALL | ~0.19–0.54s | early ~68–69; later ~89 | The voiced tail is noticeably higher |
| WE | ~0.62–0.87s | voiced core ~79 | Do not treat spurious ~180Hz harmonic picks as a true rise |
| PLAY | ~0.98–1.31s | early ~101; late ~89–91 | Pitch **falls** through the vowel |
| A | ~1.38–1.61s | ~90–92 | Stay ~91 throughout the pronounced standalone AY |
| GAME | ~1.73–2.08s | middle ~127–128; tail ~120–122 | Approximately steady then mild decline; **not** 180 Hz throughout |

Interword low-energy valleys in the original clip occur near 0.579, 0.898, 1.332 and 1.636 seconds. **Preserve** the existing Take 6 phrase score of 17 R0 bytes and 45 frames (~2.191 seconds), the explicitly pronounced standalone A (SSI phoneme AY $45), and its moderate staccato pauses. Only alter R1 pitch timing.

## Mapping to real SSI-263 register controls

The native mode-3 SSI model at XCK=1,020,000Hz produces quantized pitch targets. Changes in R1 glide in real chip time, so prepare PLAY and GAME pitches during preceding **PA** records where possible.

| At R0 event index | R1 value | Approx target Hz | Purpose |
|---|---|---|---|
| Before index 0 | $1B | 68.7 | Start SHALL low |
| 2 (L of SHALL) | $53 | 90.6 | Gentle rising tail on SHALL |
| 4 (W of WE) | $3B | 79.7 | WE stays low |
| 6 (PA before PLAY) | $63 | 99.6 | Prepare higher PLAY start in silence |
| 9 (AY of PLAY) | $53 | 90.6 | PLAY falls; standalone A stays here |
| 12 (PA before GAME) | $83 | 124.5 | Prepare moderate GAME pitch during PA and /g/ closure |

No R1 updates in R0 indices 13–15 (`KV AY M` = GAME), preventing the previously disliked mid-word upward sweep. $83 (~124.5Hz) is the closest available native pitch target to the film's voiced GAME body near 128Hz (next quantized target, $8B, is ~132.8Hz). The final natural drop in the movie is not forced by an artificial envelope.

The R1 command **must not** be issued at R0 event 11 (standalone A); that was a mistake in Take 5/6 relative to movie pitch since it made the AY article start gliding toward GAME too early.

## Separate demo files

- `wargames_slot4_film_pitch.s` → CI artifact `wargames_film_pitch.raw` (Apple II/IIe slot 4, load at $6000, call 24576).
- `render_wargames_film_pitch.c` → CI artifact `wargames_ssi263_film_pitch.wav` (original carrierless SSI phoneme rendering, 22,050Hz, 16-bit mono).
- Existing Take 1–6 artifacts and the R11 FPGA + MCU code are unchanged.
- GitHub Actions requires the 6502 source and C renderer to have identical 17 phoneme bytes and all six R1 event settings, validates the 45-frame timing and rejects clipped PCM, and checks actual model F0 checkpoints. This is an independently testable take, not a claim of sample-exact recreation of a film voice.

**Note:** The original recording is a processed human performance. Even if F0 and word timings align, timbre/formants and articulation will differ from real John Wood dialogue. The user's listening assessment and an optical recording of the Apple IIe remain the final quality checks.
