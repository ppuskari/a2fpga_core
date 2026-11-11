# WarGames / Joshua-inspired SSI-263 demo — "Shall we play a game?"

**Intent:** Play the correct brief `WarGames` (1983) WOPR line from an actual SSI-263 phoneme stream on the Apple IIe slot-4 Enhanced Mockingboard. This does **not** embed John Wood's copyrighted soundtrack or pretend the movie used the SSI-263 chip.

The original WOPR/Joshua voice is **actor John Wood**, edited by recording his lines as **reverse word sequences** and reassembling them in natural order to suppress contextual inflection, then applying post effects. Director John Badham describes the process: https://sffgazette.com/sci_fi/wargames-has-turned-40-would-you-like-to-play-a-game-a5513

The emulation approximation uses:
- fixed SSI R1 inflection = `$63` (reduced pitch movement)
- slower SSI R2 rate = `$48`; full sentence in the C model is ~2.145s
- SSI R3 = `$69` (articulation 6, amplitude 9; host output peak 28433 PCM16 without clipping)
- SSI R4 = `$E8`, the Demo Disk 1 compatible filter clock divider
- 17 phoneme/pause records, native SSI ROM and no external PCM attack shaping; no artificial carrier
- completion explicitly sends **SSI R3=$80 power-off**, as a test of the emulated power-down path

These choices are a *first pronunciation preset*, not a claim of a studio-matched WOPR tone. Pitch, pacing and phoneme variants can be tuned from optical recordings.

## Actual ROM phonemes

The source of the names and code values is the pinned `reference/ssi263/pico-v1.0.1/rom_bits.csv`. SSI R0 bits 5:0 carry a ROM code; bits 7:6 carry duration (0=4 frames, 1=3, 2=2, 3=1). With `R2=$48`, a frame is about 48.2ms.

| Word | Phonemes | ROM codes | Exact SSI R0 bytes |
|---|---|---|---|
| shall | SCH AE L | 32 0C 20 | B2 4C 60 |
| pause | PA | 00 | 00 |
| we | W E | 23 01 | A3 41 |
| pause | PA | 00 | 80 |
| play | P L AY | 27 20 05 | A7 A0 45 |
| pause | PA | 00 | 80 |
| a | AH (unstressed /uh/ approximation) | 0E | 8E |
| pause | PA | 00 | 80 |
| game | KV AY M | 26 05 37 | A6 45 77 |
| final release | PA | 00 | 00 |

`KV` is the **voiced velar stop** for /g/, rather than the unvoiced `K`. `SCH` is the /sh/ phoneme, not the individual letters S/C/H.

## Apple II 6502 executable

`wargames_slot4.s` contains a standalone 6502 program at `$6000` that:
1. Saves the right VIA PCR; configures CA1 falling-edge detection and polls IFR bit 1 rather than forcing a dedicated IRQ handler.
2. Powers down SSI, loads the initial PA and mode 3, sets R4/R2/R1/R3, then issues the 17 R0 records on their A/R requests.
3. Uses a bounded A/R wait so it cannot wedge indefinitely if the board is absent or a poll is missed.
4. Sends `R3=$80` to power off the SSI and restores the PCR and processor flags.

**It is a slot-4-only demo** by default. Do not run simultaneously with another program already controlling the Mockingboard right VIA/SSI.

GitHub Actions builds:
- `wargames.raw` — flat 6502 machine code intended for load at **$6000**
- `wargames_ssi263.wav` — a host preview from the pinned real Pico C model, carrierless, 22.05 kHz mono

Download these from the branch's latest passing GitHub Actions `r11-wargames-ssi263-demo` artifact. The WAV is a preview; the Apple II sound comes from the emulated SSI live, not from WAV playback.

To assemble manually from the repository root with `ca65` and `ld65` (cc65 toolchain):

```powershell
ca65 -o .\wargames.o .\examples\ssi263_wargames\wargames_slot4.s
```

```powershell
ld65 -C .\examples\ssi263_wargames\apple2_6000.cfg -o .\wargames.raw .\wargames.o
```

To use with an Apple II disk image editor such as CiderPress, import the **raw bytes** as a binary program with load address `$6000` (ProDOS BIN auxiliary type `$6000`, or DOS3.3 B binary with correct load address). Do not double-prefix the four-byte DOS binary header if the disk editor constructs that header itself. Then from Applesoft BASIC, once the file is on the mounted disk:

```basic
BLOAD WARGAMES,A$6000
CALL 24576
```

You may rename the disk file; its executable address remains `$6000`.

## Host WAV preview

Linux/macOS shell at repository root, or equivalent command paths on Windows with GCC:

```sh
gcc -std=c99 -O3 -fsingle-precision-constant -DSSI263_DIGITAL_NO_CARRIER=1 -DSSI263_R8_FAST_SWELL=1 -Ireference/ssi263/pico-v1.0.1 examples/ssi263_wargames/render_wargames.c reference/ssi263/pico-v1.0.1/ssi263.c reference/ssi263/pico-v1.0.1/ssi263dsp.c -lm -o wargames_preview
```

```sh
./wargames_preview wargames_ssi263.wav
```

The 6502 program and the host WAV program use **identical 17 R0 phoneme bytes**, verified by CI. The host WAV cannot emulate the Apple II 6522 interrupt timing or the FPGA's 512-sample PCM re-priming delay; those require hardware capture.

## What to listen for and tune

- Is the first `SCH` present after >15 seconds of FPGA PCM suspension?
- Is `we` too bright? Adjust R1 inflection together in both sources, and keep the 22.05k carrierless baseline.
- Does `game` sound like /kaym/? Keep `KV` rather than `K`; compare `AY` vowel alternatives only after hearing hardware.
- Is the pacing too quick/slow? Change R2 high nibble in *both* Apple II and preview C files; lower nibble affects rate control, so preserve `8` for the first experiment.
- Does the explicit R3=$80 completion clear output without a click and send power-off to the FPGA? Capture the end via optical.
- Do not add a studio-vocoder or recorded John Wood samples to the baseline: the test is specifically **authentic SSI phoneme synthesis** with WOPR-inspired prosody.

## Licensing and fidelity

The PINNED C model in `reference/ssi263` retains its own license and attribution. This demo uses its phoneme-ROM mapping. The voice in the 1983 film is an edited human performance; we are producing an original sound through an emulated SSI-263, not duplicating or distributing the film audio.
