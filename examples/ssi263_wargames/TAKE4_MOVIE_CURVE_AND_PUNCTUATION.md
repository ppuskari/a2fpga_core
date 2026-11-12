# WarGames WOPR SSI-263 Take 4 / 4B — Correct pitch and sharper word spacing

## Important comparison-file correction

The user's `gametake3compare.wav` is a 4.584-second stereo concatenation: the supplied movie recording is followed by **Take 1**, although the user thought it was Take 3. This was proven by comparing the second segment against the actual GitHub Actions artifacts (run 43250419305): normalized correlation approximately **0.9999999** with `wargames_ssi263.wav` (Take 1), versus approximately **0.0645** with `wargames_ssi263_film_timing.wav` (Take 3).

Consequently, the flat ~100Hz voice in that combined recording **does not diagnose broken R1 pitch automation in Take 3**. The original Take 1's fixed R1=$63 accounts for it. A real Pico model state probe (`tests/ssi263_hybrid/test_wargames_pitch_probe.c`) confirms that Take 3 in the actual CI source transitions through approximately 76.6, 83.0, 90.6 and 124.5 Hz.

The uploaded movie dialogue and combined WAV are **not checked into the repository**. All demo WAVs are generated entirely from the authentic SSI-263 physical ROM through the carrierless Pico C model.

## Film-derived voiced fundamental frequency (estimated)

The movie clip is ~2.194 seconds, 44.1kHz stereo. Framewise autocorrelation/YIN-like analysis of voiced portions yields approximate pitch groupings:

| Segment | Movie F0 | Actual Take 3 F0 | Take 4 and 4B target / measured model |
|---|---:|---:|---:|
| SHALL | ~69Hz | ~76.6Hz | **68.7Hz** (`R1=$1B`) |
| WE | ~79Hz | ~83.0Hz | **79.7Hz** (`R1=$3B`) |
| PLAY / A | ~91Hz | ~90.6Hz | **90.6Hz** (`R1=$53`) |
| GAME voiced onset | ~128Hz | ~124.5Hz | starts ~124.5Hz (`R1=$83`), then glides |
| GAME final vowel/nasal | ~175–185Hz | ~124.5Hz | **181.1Hz** (`R1=$AB`) |

These are estimates from processed film audio and actual modeled synthesized glottal F0, not proof of the source actor's unprocessed voice pitch.

The main Take 4 changes versus Take 3:
- initial R1 lower from `$33` to `$1B`
- WE R1 from `$43` to `$3B`
- keep PLAY/A at `$53`
- initial GAME target `$83` during the preceding PA
- second pitch step to `$AB` at index 14, on GAME's `AY` phoneme, gliding from ~124.5 to ~181Hz before the final nasal M
- shortens the WE pause by one ~48ms SSI frame and increases the final M phoneme by one frame; keeps **17 records, 45 frames, 2.191 seconds** overall

## Two controlled alternatives

| Parameter | Take 4: movie pitch | Take 4B: extra staccato |
|---|---|---|
| Pitch writes | identical 5-level rise | identical 5-level rise |
| Typical interword PA | ~48ms | **~96ms** |
| Voiced vowels | full baseline | one ~48ms frame shorter in SHALL, WE, PLAY, A |
| Total frame count | 45 | 45 |
| Duration | 2.191s | 2.191s |
| 10ms blocks under -55dBFS in synthesized WAV | 15 | **35** |
| Exact-zero PCM16 fraction | ~4.2% | **~12.0%** |
| Peak | -0.45 dBFS | -0.45 dBFS |
| R11 FPGA/BL616 changes | none | none |

Take 4B deliberately introduces more separation than the movie reference itself; it is a **listening alternative**, not a more precise reproduction of the soundtrack.

## Sources and artifacts

| Variant | Apple II 6502 source | Host C source | GitHub artifact WAV | Apple II raw program |
|---|---|---|---|---|
| Take 3 | `wargames_slot4_film_timing.s` | `render_wargames_film_timing.c` | `wargames_ssi263_film_timing.wav` | `wargames_film_timing.raw` |
| Take 4 | `wargames_slot4_movie_curve.s` | `render_wargames_movie_curve.c` | `wargames_ssi263_movie_curve.wav` | `wargames_movie_curve.raw` |
| Take 4B | `wargames_slot4_punctuated.s` | `render_wargames_punctuated.c` | `wargames_ssi263_punctuated.wav` | `wargames_punctuated.raw` |

All Apple II files load as a raw `BIN` at **$6000**, then execute with `CALL 24576`. Avoid double-inserting a DOS3.3 binary header when importing raw files with disk tools. The programs poll right VIA CA1 for SSI phoneme completion and send `R3=$80` power-off before returning to Applesoft.

The final ZIP is generated in the `r11-wargames-ssi263-demo` artifact of the `ssi263-p10r11-spi-suspend-wargames.yml` workflow.

**CI validation:** 6502 assembly, C99 compilation, identical 17 SSI R0 records in both implementations, all R1 pitch-change points, no PCM clipping, exact 2.191s output. Real Pico C-model state snapshots for Take4 at word checkpoints: 68.7, 79.7, 90.6, 165.1 and 181.1 Hz. FPGA R11 PCM suspend and R10 idle regression tests continue passing unchanged.

**Hardware qualification:** Running the Apple II `.raw` programs, real SSI A/R event timing, audio playback through R11's FIFO wake/reprime, and optical comparison still require a physical test. No BL616 Stage2 or FPGA bitstream update is necessary.

## Windows update

At an already cloned repo:

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11; git pull --ff-only
```

The preferred next test is to listen to all three labeled WAV previews **from the same final artifact**, then import `wargames_movie_curve.raw` and/or `wargames_punctuated.raw` to the Apple II. Capture the optical output if a first-consonant or A/R timing discrepancy appears.
