# A3 live audio: restored SynthLAB ROM and stronger Original AY

This branch starts from petar/audiocfg-live-no-lock-20261117.
The working live mode switch, no lock, M641 Disk II boot/reset path,
BL616 firmware, Hybrid SSI263 speech, and Native/Shared audio wiring
are unchanged. **Only the Enhanced FPGA needs rebuilding/flashing.**

## Required SynthLAB extraction

The seven authentic SynthLAB piano sustains are deliberately NOT in Git.
The FPGA bridge `boards/a2n20v2-Enhanced/hdl/mb_doc_bridge.sv` reads
`hdl/piano_multisustain.mem` using `$readmemh`. A build that omitted
this generation step can produce silent DOC music despite working
Original YM2149 and hybrid SSI263 speech.

At the repository root, before launching Gowin:
`py -3 tools/extract_synthlab_piano.py --download`
`py -3 tools/extract_synthlab_piano.py --check`

The extractor requires authentic System 6.0.4 SynthLAB source disk
(MD5 fa4f143dd899d0cc4c8ed9c9e41b7d37), verifies each sample's
FNV and creates 1408 little-endian 32-bit hex words (5632 bytes).
The packed FNV32 must be 170BB8B3, without $00 stop bytes.
Copyrighted PCM is ignored by Git and should NEVER be committed.

For offline use, obtain your original disk image and run:
`py -3 tools/extract_synthlab_piano.py --disk "C:\\path\\to\\synthLAB.po"`

The Enhanced Gowin `prebuild.tcl` now generates this ROM if missing
(using the verified source URL), and ALWAYS validates its fingerprint.
Invalid/missing samples fail before synthesis, with explicit error.
`--check` uses no network access.

## Original YM2149 music/FX gain

The reported Original mode level was approximately -24 dBFS,
target -2 dBFS. The Original AY/FX high-pass samples alone gain
201/16 = 12.5625x, +21.98 dB, implemented as shift-and-add with
signed saturation. The music signal is bounded at +/-18508 before
the unchanged SSI263 speech summation. The existing 45/32 HDMI
stage (+2.96 dB) then receives a final Original-only limiter of
+/-26028, approximately -2 dBFS.

Speech is NOT multiplied by the new gain. Enhanced DOC keeps
its separate existing 8x/-2dBFS calibration. Shared and Native
modes retain their original gains, as do reset and live switching.

A fixed +22 dB gain is a calibration starting point, not measured
post-change performance; dense YM channel mixes may reach the
limiter. Observe the 1-second HDMI clip history and listen for
distortion, then adjust if needed.

## Source gates and hardware test

`py -3 tools/test_audiocfg_m641_boot.py`
`py -3 tools/test_audiocfg_live_mode.py`
`py -3 tools/test_audiocfg_samples_gain.py`
`py -3 tools/extract_synthlab_piano.py --download`
`py -3 tools/extract_synthlab_piano.py --check`

Open `boards/a2n20v2-Enhanced/a2n20v2_enhanced.gprj`.
Do a clean Gowin synth/P&R and confirm timing and that the piano
ROM was incorporated. Flash the FPGA `.fs` only, preserving
the already working BL616 Stage2 audio selector and Stage1.

1. Set Enhanced via SAVE + APPLY LIVE; restart demo program, and
   confirm DOC piano notes plus speech.
2. Set Original and restart demo; measure optical HDMI at 44.1kHz,
   target AY peaks near -2 dBFS with no persistent clipping.
3. Switch back live with no Apple/Disk II reboot.
4. Evaluate FX and piano timing separately; FX sample bank builder
   `tools/build_mb_doc_fx_bank.py` remains a diagnostic not yet
   connected to DOC OSC6/7 or the main preload, so don't claim
   that FX samples are restored by this commit.

No synthesis, flash or real-audio listening result is asserted by
these source changes. Keep last known working .fs for rollback.
