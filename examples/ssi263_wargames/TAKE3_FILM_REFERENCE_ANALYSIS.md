# WOPR Take 3 — timing derived from the high-quality movie dialogue sample

This is a **reference-driven** revision of the standalone Apple II SSI-263 demo, not a change to the R11 FPGA PCM suspension core or BL616 firmware. It does **not** embed or distribute the copyrighted film recording. Only these manually checked timing and pitch measurements are retained.

## Supplied film clip

- Local reference as supplied by the tester: `shallweplayagame.wav` (**not checked in**)
- 44,100 Hz stereo PCM, 96,768 frames, 2.1942857 seconds
- L/R waveform correlation approximately 0.995
- Original soundtrack contains low-level background audio; its interword valleys are low energy, **not** exact PCM zeros

Five-millisecond RMS envelope, smoothed to identify the four strongest boundaries between the five spoken words:

| Transition | Measured trough time | Peak attenuation at trough | Approx. low-energy window (RMS below -30dBFS) |
|---|---:|---:|---|
| SHALL / WE | 0.579s | -37.0dBFS | 0.549–0.594s (**45ms**) |
| WE / PLAY | 0.898s | -39.9dBFS | 0.873–0.948s (**75ms**) |
| PLAY / A | 1.332s | -41.3dBFS | 1.312–1.347s (**35ms**) |
| A / GAME | 1.636s | -37.8dBFS | 1.621–1.651s (**30ms**) |

The key discovery is **short, nearly silent boundaries plus abrupt phoneme consonant attacks**, not half-second word pauses. The prior Take 2 (2.839 seconds, 22 records) deliberately increased pause duration but was too slow compared with the real movie clip.

An approximate YIN fundamental-frequency estimate for the processed human film voice suggests early sections in the 70–90Hz region, a middle around 90Hz and a distinctly elevated final word around 120–130Hz. These values are **guideposts**, not a claim of original unprocessed actor vocal pitch or true instantaneous SSI register targets.

## Revised 45-frame SSI-263 score

Keep the Demo Disk-compatible SSI R4 `$E8`, mode 3, rate R2 `$48`, control/volume R3 `$69`. A single frame is approximately `4096*(16-4)/1020000 = 0.04819s`.

| Word | Actual SSI ROM syllable records | Programmed word+pause | Expected group start |
|---|---|---:|---:|
| SHALL | `SCH $72`, `AE $0C`, `L $20`, `PA $C0` | 12 frames / ~578ms | 0.000s |
| WE | `W $A3`, `E $01`, `PA $80` | 8 frames / ~386ms | 0.578s |
| PLAY | `P $E7`, `L $A0`, `AY $05`, `PA $C0` | 8 frames / ~386ms | 0.964s |
| A | `AH $0E`, `PA $C0` | 5 frames / ~241ms | 1.349s |
| GAME | `KV $66`, `AY $05`, `M $77`, `PA $80` | 12 frames / ~578ms | 1.590s |

The `KV` velar closure begins around 1.59 seconds, but its voiced vowel follows ~145ms later at approximately 1.73 seconds, matching the movie's last-word release and rising pitch after the 1.636s trough.

**Pitch/intonation:** Rather than retaining Take 1/2's single R1 value of `$63`, Take 3 sends actual SSI R1 writes on word boundaries:

- SHALL: `R1=$33` (model target ~77Hz)
- WE: `R1=$43` (target ~83Hz)
- PLAY and A: `R1=$53` (target ~91Hz)
- Just before GAME, during the final A pause: `R1=$83` (target ~124Hz), allowing native pitch glide before the voiced onset

These targets derive from the Pico C model's SSI pitch equation for `R2=$48` and `XCK=1,020,000`. Native pitch glide means the instantaneous rendered pitch need not equal the target at the instant of writing. They remain an **approximation** to the manipulated soundtrack and must be judged by listening to a real FPGA/HDMI optical capture.

## Files and playback

- `wargames_slot4_film_timing.s`: real 6502 code; uses slot-4 SSI register writes and VIA CA1 A/R; load at `$6000`, `CALL 24576`
- `render_wargames_film_timing.c`: exact corresponding SSI R0 bytes and R1 changes rendered through the pinned Pico carrierless model at 22.05kHz
- CI builds `wargames_film_timing.raw` and `wargames_ssi263_film_timing.wav` in the **same ZIP** as Take 1 and Take 2
- In an Apple II DOS or ProDOS disk image, import `wargames_film_timing.raw` as a binary with load address `$6000`, and run it using `CALL 24576`
- The original `wargames.raw` and `wargames_staccato.raw` remain available for A/B testing
- Explicit `R3=$80` power-off is sent at the end of all 6502 takes

**No FPGA rebuild or BL616 Stage2 reflash required** for this standalone demonstration. R11's speech synthesis implementation and SPI suspend behavior remain unchanged.

**Acceptance:** compare the 2.194s film reference vs the independently rendered take on (a) word onset/low-energy valley positions, (b) audible sharpness at SCH/P/KV, (c) absence of clipping, (d) raised yet smooth `GAME` pitch and (e) the first word after FPGA PCM suspension. Fine timing remains quantized to 48.19ms SSI frames; sample-exact timing is not possible using only original chip phoneme duration codes.
