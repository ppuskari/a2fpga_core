# P8 — SSI-263P complete-chip reconstruction (engineering baseline)

## Correcting the P7 scope error

P7 was a new phoneme-dependent **sound renderer** connected to
the existing P6 SSI register controller. It did not implement
the SSI-263 silicon model and is not an acceptable fidelity baseline.
The P7 die-derived ROM did not, by itself, recreate the vocal tract.

This P8 branch starts from the **hardware working combined P6**
rather than P7. P6 music, AY FX, DOC, HDMI gain, SSI socket and right
VIA CA1 are **not modified on this branch**. Do not call P8 golden.

## The authoritative software reference

Pinned, MIT-licensed source from
[kue-m/mockingboard-pico](https://github.com/kue-m/mockingboard-pico),
whose SSI engine is derived from Tamas Geczy's research:
[ssi263-speech](https://github.com/lprazdnik/ssi263-speech).
See `reference/ssi263/pico-v1.0.1` for:
- `ssi263.c` complete chip engine, including register/phoneme timing,
  filter clock, six transitioning fields, glottal/noise excitation,
  F1-F5 vocal tract, closure/early A/R lookahead, HP and decimation
- `ssi263.h`, `ssi263_defaults.h`, `ssi263dsp.c`
- `rom_bits.csv`: original 64 x 29 silicon ROM cells
- `NOTICE.md` and `LICENSE` preserving original MIT attribution.

`reference/ssi263/p8_reference_gate.c` compiles this exact C source
and renders deterministic 50 kHz PCM from a sequence of the real
Mockingboard Demo Disk SSI five-register commands. Its register and
output checks run in GitHub Actions.

## New FPGA organization

The **independent** `hdl/mockingboard/ssi263_p8_chip.sv` owns:
- CPU-visible R0–R4 register file and power-up CTL handling
- XCK tick-based duration state and A/R output
- R4-controlled switched-capacitor filter clock:
  `fc = XCK / (2*(256-R4))`
- R1/R2 pitch target and glide state
- 64 decoded parameter records from the die-ROM
- six internal transitioning controls: F1/F2/F3/NAS/VA/FA
- original non-MAME glottal pulse and LFSR noise source
- **one five-stage serial filter datapath**, F1→F2→F3→F4→F5,
  with b02-controlled noise injection
- final HP, held PCM and power-down mute.

Dedicated ROMs:
- `boards/a2n20v2-Enhanced/hdl/ssi263_p8_params.mem`, 64 words
- `boards/a2n20v2-Enhanced/hdl/ssi263_p8_coefs.mem`, 50 words.

The new RTL is now connected as an **opt-in compile-time alternate**
chip path through the existing SSI socket and HDMI speech mixer.
The toggle is `MOCKINGBOARD_SSI263_FULL_CHIP_ENABLE=0` by default
in `boards/a2n20v2-Enhanced/hdl/top.sv`, so P6 is unchanged.

Switching this parameter to 1 compiles the independent P8 register
and DSP module instead of **both** legacy `ssi263_control` and
`ssi263_voice`. Do NOT ship or flash it for audio-quality acceptance
until waveform/spectral equivalence and Gowin resource/timing checks
are established. The optional wiring is currently useful for
register-level integration verification.

## Current verification

- [x] Exact Pico upstream chip source and ROM pinned in repository
- [x] MIT attribution preserved
- [x] Native reference C compiles and generates nonzero PCM
- [x] Independent chip RTL compiled and simulated on isolated controls
- [x] Independent Verilator lint passes (warnings allowed)
- [x] Optional full-chip slot integration with P6 selected by default
- [x] Demo Disk 1 register/CA1 sequence in stand-alone chip path
- [ ] Exact R0-R4, CTL, A/R, pitch/glide, and duration register
      equivalence against a captured real Demo Disk register stream
- [ ] Dynamic six-field latch and transition equivalence
- [ ] Exact switched-capacitor F1/F2/F3/F4/F5 response per ROM code
- [ ] Correct closure timing, early A/R and held-write behavior
- [ ] Noise shaping, fricative routing, glottal pulse timing equivalence
- [ ] Output S/H, anti-alias FIR/decimation, carrier and level match
- [ ] Full data-path waveform correlation against pinned C model
- [ ] Spectrogram, formant peak, F0, RMS/peak and phoneme onset
      comparison against uploaded `ssinativespeech.wav`
- [ ] Gowin synthesis/placement/route, DSP count, resource and slack
- [ ] Real Apple IIe Mockingboard Demo Disk 1 audio acceptance

**Those unchecked boxes are requirements, not optional polish.**

Do not mistake the current stand-alone chip RTL's ability to generate
PCM for fidelity to the actual SSI263. More work is required before
wiring it into the production music/speech build.

## Comparison/acceptance methodology

1. Extract/replay the actual Demo Disk 1 five-register event stream
   with time stamps in XCK cycles; preserve the working P6 CA1 protocol.
2. Run exactly that event stream through pinned C engine and P8 RTL.
   Align by register/phoneme events, not inferred sound boundaries.
3. Compare R0-R4 readback, power, A/R edge cycle, generated fc tick,
   phoneme start/end cycle and per-field latch value. Require exact
   matches for digital control state.
4. Compare impulse responses of all five filter sections and then
   complete phonemes; require bounded fixed-point error (tolerance
   derived from the chosen output architecture, NOT guessed).
5. Compare recorded native reference with the synthesized result,
   loudness-normalized for timbre; avoid 'fixing' formant mismatch
   by amplifying output.
6. Only after passing these gates: connect the P8 chip core to the
   existing Apple II slot bus and HDMI mixer with a build-time
   fallback to the unchanged P6 output.

## Operational notes

`MB_SPEECH_GAIN_NUM=3` is a P6 workaround, not an intrinsic SSI
analog gain value. When the full-chip output path is integrated,
calibrate amplitude at the **chip output stage**, and revisit
the HDMI level separately while preserving piano and effects levels.

**Current P8 limitation:** the FPGA includes a preliminary fixed-point
implementation of every major chip block, but specific analog transfer
functions, early request handling, closure articulation, noise routing,
field interpolation and audio decimation still differ from the
upstream C model. Do not label it a verified complete SSI263 core.

CI: `.github/workflows/ssi263-fullchip-p8.yml`.
Reference test and isolated RTL simulation are automated. No Gowin
or silicon-accuracy claim can be made from a passing CI run.
