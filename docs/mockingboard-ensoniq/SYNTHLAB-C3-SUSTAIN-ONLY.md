# SynthLAB original C3 sustain — isolated A/B playback experiment

**Branch:** `petar/mb-doc-synthlab-c3-sustain-only-20261106`
**Base:** `petar/mb-doc-synthlab-piano-c3-8k-20261106` (8KB repeated-attack failure).

## Why

The 8KB SynthLAB `Piano C3` is the ATTACK sample, not a periodic steady-state piano waveform. Looping it continuously produces rhythmic repeated hammers. The bridge also lacks AY note-on detection/retrigger, so it can begin at arbitrary phases. This branch is a deliberately limited A/B diagnostic: replace the repeated attack with the actual original `~Piano C3` SUSTAIN wave.

## Authentic sample

- Same verified Apple IIgs System 6.0.4 `synthLAB.po`, `SEQ.AND.INSTR/PIANO.WAV`.
- Original `~Piano C3` wave definition index **7**, 1024 PCM bytes at original DOC sound RAM address `$1800`, waveform size code **2**.
- All bytes nonzero, native DOC unsigned-offset binary; FNV-1a32 **430E4B0A**.
- The companion `Piano C3` ATTACK is 8192 bytes at `$8000`, size code 5, previously looped in error.
- The original PCM is *not committed*; an extractor creates a local `.mem` file from the archived disk.

## Build in PowerShell 5.1

Clone into a separate directory:

```powershell
git clone --branch petar/mb-doc-synthlab-c3-sustain-only-20261106 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-c3-sustain
```

Extract the authentic sustain sample:

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-c3-sustain; py -3 tools\extract_synthlab_piano.py --download
```

This generates `boards\a2n20v2-Enhanced\hdl\piano_c3_sustain.mem` (256 x 32-bit words). The script validates the original 800K ProDOS-order disk image MD5 and the 1KB PCM checksum.

Open `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj` in Gowin. Verify `AUDIO_MODE_MB_DOC=1'b1`, successful `.mem` read, all MB-DOC logic retained, and timing/bitstream success. Program **FPGA only**, never BL616 firmware. Preserve the previous working modeled-piano P3 `.fs` for rollback.

## DOC test parameters

- Preload 1024 sample bytes at bank-0 sound RAM `$0000..$03FF` as 256 acknowledged 32-bit writes.
- Original six DOC voices, same stereo routing and AY envelope semantics.
- WTP `$00`, RTS `$12`: WTS2 (1024 bytes), RES2. The sustain waveform contains approximately four note cycles, so WTS2/RES2 keeps the old `FC=93623/max(AY_period,1)` conversion as a pitch *approximation*.
- The wave repeats continuously. **No sampled hammer attack**, note-trigger detection, swap-mode, or automatic envelope beyond the original AY envelope.

## Expected result

Less rhythmic hammer repetition than the 8KB attack-only build; probably a softer, somewhat organ-like piano sustain. This is NOT a complete fix: the real solution is one-shot attack followed by sustain looping, controlled by new AY-note detection, and eventually keyboard-zone multi-samples. The sample is sourced from an authentic instrument, but its musical pitch should still be checked on Apple IIe hardware.

## Test

GitHub Actions generates the sample from the original disk then runs the Icarus six-voice/PCM fingerprint and Verilator YM-envelope regressions. This cannot establish actual Gowin resource/timing or sound quality.
