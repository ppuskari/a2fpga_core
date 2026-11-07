# Authentic Apple IIgs SynthLAB Piano C3: 8 KB Mockingboard DOC experiment

Branch: petar/mb-doc-synthlab-piano-c3-8k-20261106
Based on working P3: petar/mb-doc-piano-wavetable-20261106
Status: RTL test pending; Gowin synthesis and Apple IIe playback not yet hardware validated.

## Original source, verified from the real disk image

Apple System 6.0.4 SynthLAB installation disk, 800 KB ProDOS-order synthLAB.po.
- ProDOS folder: SEQ.AND.INSTR
- File: PIANO.WAV (ProDOS type $D8, exactly 67840 bytes); this is NOT a RIFF WAV.
- File layout: 256-byte header, 2048 bytes of wave definitions, 65536-byte DOC RAM bank.
- Wave definition index 6: Pascal name "Piano C3", size code 5, original address $8000, 8192 PCM bytes.
- Companion wave index 7: "~Piano C3", 1024 bytes (not used in this test).
- All 8192 PCM bytes nonzero (DOC $00 means halt); FNV-1a checksum B4AF4568.
- synthLAB.po MD5: fa4f143dd899d0cc4c8ed9c9e41b7d37.

Sources:
https://github.com/gungwald/apple-ii-dev/blob/main/var/apple2gs/Apple_IIGS_System_6.0.4/PO%20Disk%20Images/synthLAB.po
https://mirrors.apple2.org.za/Apple%20II%20Documentation%20Project/Software/Operating%20Systems/Apple%20IIGS%20System/Disk%20Images/Apple_IIGS_System_6.0.4/PO%20Disk%20Images/synthLAB.po

To avoid redistributing original Apple PCM, the sample is generated locally using a Python script from the original disk. The generated .mem is gitignored and MUST exist before Gowin synthesis. No synthetic fallback exists.

## Windows PowerShell 5.1

Clone into a NEW directory (keep the old working P3 .fs intact):

    git clone --branch petar/mb-doc-synthlab-piano-c3-8k-20261106 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-synthlab

Generate the exact original PCM:

    Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-synthlab; py -3 tools\extract_synthlab_piano.py --download

Alternatively supply a local disk image:

    py -3 tools\extract_synthlab_piano.py --disk "C:\mydisks\synthLAB.po"

The extractor validates the disk MD5, the Apple MIDI Synth Wave header/definition, and the PCM checksum; it writes:
boards\a2n20v2-Enhanced\hdl\piano_c3_attack.mem
(2048 lines of 32-bit hexadecimal, packed little-endian).

Open in Gowin:
C:\AppleIIgsDev_02\a2fpga-mb-doc-synthlab\boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj

The .gprj includes the generated ROM asset, and Enhanced top.sv retains AUDIO_MODE_MB_DOC=1'b1. Confirm sound_glu(MB_DOC_MODE=1'b1), Mockingboard and mb_doc_bridge are compiled and NOT optimized away. If Gowin reports missing/uninitialized PCM ROM, STOP; do not program that bitstream.

Check BSRAM use and timing; this 8KB ROM may use more FPGA block RAM than the 256-byte modeled wavetable. Keep a distinct .fs filename. Flash only the FPGA bitstream, not the BL616 MCU (no Stage 1/Stage 2 firmware changes).

## Temporary hardware behavior

The known 8192-byte Piano C3 sample is relocated to DOC bank 0 addresses $0000-$1FFF and preloaded via 2048 acknowledged 32-bit SDRAM writes. One RAM_FETCH state gives the registered ROM output time to settle before each write.

All six AY-driven voices reference the same 8KB wavetable at WTP=$00 with RTS=$2F (WTS 5=8KB, RES 7=24-bit phase). The 8192-byte sample contains approximately 32 note cycles. To preserve the prior note frequencies, the bridge multiplies the former frequency quotient by 4 (128/32 for RES7 vs old RES0), saturating at $FFFF. This is approximate tuning, not calibrated to the original instrument metadata.

The unchanged P3 YM2149 envelope, stereo mapping, reset handling and -2 dBFS HDMI cap remain in place. AY noise remains unimplemented.

IMPORTANT: this is a FREE-RUN LOOP of the sample's recorded attack, NOT SynthLAB's original piano instrument engine. The separate 1024-byte sustain sample, note triggering, oscillator swap, and multisampling are future tasks. Expect possible repeated attacks/tremolo every ~32 pitched cycles.

## Regression

GitHub Actions runs the sample extractor from the archived disk, then Icarus tests all 2048 SDRAM writes, no zero bytes, complete FNV32 hash, six voices, WTS5/RES7 pitch conversion and envelope/reset tests. Verilator tests native YM2149 envelope shapes and retriggering. Hardware synthesis and sound quality remain to be validated.

Rollback to the last working P3 modeled piano .fs anytime.
