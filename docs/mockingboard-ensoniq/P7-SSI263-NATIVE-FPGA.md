# P7: native SSI-263 FPGA core integration (development, NOT speech fidelity release)

Parent: P6 `petar/mb-doc-p6-speech-level-calibration-20261107`
Baseline commit: `987be494998e45d561cb4b372c0149888493c3b9`

## Current integration

- Same tested Apple II write strobe, original `ssi263_control.sv`, right VIA CA1
  IRQ, AY/DOC music, FX, seven piano zones, HDMI gain and limiter.
- New isolated `ssi263_native_rom.sv` uses the 64x29 decoded SSI-263
  phoneme records published in Robert Elmer's Casso (MIT license).
- New `ssi263_native_voice.sv` is an **FPGA-native diagnostic excitation
  renderer**, NOT a reconstruction of the chip's vocal tract.
- `MOCKINGBOARD_SSI263_NATIVE_SELECT=0` by default: the P6 waveform path
  remains the active speech implementation, unchanged. Set to 1 in the top
  parameters to compile the new native voice instead (generate-time selection).
- Both audio paths feed the same existing speech PCM mixer; the DOC is not
  required for speech. No BL616 firmware change.

## Validation

`bash tools/test_ssi263_native.sh` (requires Icarus Verilog and vvp).
The testbench checks all ROM addresses are defined, PA is silent, nasal
codes, PCM activity for a voiced phoneme, and power-down silence.
Existing `tests/mb_ssi263` must also pass; perform the physical Demo Disk 1
speech and music tests before promoting a release.

## Work remaining for actual SSI-263 speech

The diagnostic DSP only generates a pitched pulse/noise excitation and a
basic smoothing stage. The model does **not** yet implement the full 12-bit
inflection, switched-capacitor cascade, formant transitions, articulation,
fricative routing, calibrated XCK/timing or physical output-stage response.
P7 does not claim to sound like the reference hardware. Port and validate
the C99 engine from Tamas Geczy's MIT-licensed ssi263-speech, including
source/credit notices; use Rob Elmer's Casso for independent register tests.
Both projects' included third-party firmware may have distinct licenses.

## Resource measurement (Gowin)

1. Build default P7 native selector = 0. Record LUT4, FF, BSRAM, DSP18,
   slack and clock Fmax. Compare with the same P6 build settings.
2. Set native selector = 1; synthesize, place and route, collect same values.
3. Compare P6 and P7 source and reports; don't compare only synthesis
   estimates or assume fit until timing closure is confirmed.
4. Restore selector 0 to retain working P6 speech during ongoing development.

Primary sources:
https://github.com/relmer/Casso/tree/master/specs/024-mockingboard-speech/rom-extraction
https://github.com/tgeczy/ssi263-speech
https://www.visual6502.org/images/pages/Silicon_Systems_SSI_263P_die_shots.html
