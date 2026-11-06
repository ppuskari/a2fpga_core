# Experimental piano-like DOC instrument for Apple IIe Mockingboard P3

**Branch:** `petar/mb-doc-piano-wavetable-20261106` (from the confirmed, force-enabled P3 DOC branch)  
**Purpose:** Sound experiment only. Preserve the user's previous working P3 `.fs` bitstream. Do not replace the IIgs DOC golden image.

## What is playing

The original six-voice MB-DOC P3 synthesizer shares a 256-byte nonzero triangle waveform in DOC sound RAM at address `$0000`. This branch replaces that waveform with a **256-byte, signed-8-equivalent offset-binary PCM table** built by a deterministic additive model of a piano string's sustained harmonics. The table uses 12 harmonics with progressively decreasing amplitude and independent phase offsets. The table is packed little-endian into **64 consecutive 32-bit SDRAM words**, loaded using the same known-good P3 `RAM_ISSUE/RAM_WAIT/RAM_RELEASE` handshake.

The DOC **still has six oscillators** (three left, three right), its original 256-byte table size (`RTS=$00`), `WTP=$00`, frequency conversion (`93623/P`), the real AY registers 11–13 envelope generator, hardware reset behavior, and the P3 MB-DOC-only HDMI output gain capped at -2 dBFS. **No sound-path architecture or timing changes were made.**

**Important distinction:** This is a small, *looped piano-like wavetable*, **not a digitized acoustic grand piano recording**. The DOC repeats the 256 PCM bytes each cycle; there is not yet a per-note hammer attack, long decay, separate sustain loop, velocity sensing, or multisampling. The result can sound more piano/string/keyboard-like than the original triangle, but may also resemble an organ or harpsichord, particularly on long AY-held notes. Full piano sampling would require a bigger per-voice sample/loop and note-trigger scheme.

The custom waveform is periodic and avoids `$00`, which means **HALT** to the DOC. The waveform ranges from **$10 to $EE**, and adjacent last/first sample values differ by only 11 counts. The 256 bytes have **FNV-1a 32-bit hash `B4D62B32`** in increasing address order.

## Verification

The existing Icarus bench now checks all 64 acknowledged sound-RAM writes, 256 nonzero bytes, the complete 256-byte PCM fingerprint, the first six independent DOC tone/volume/control commands, AY envelope mute and VIA-driven chip RESET. The separate Verilator bench still exercises the *actual native YM2149 envelope shape/retrigger timing*. GitHub Actions runs both on this branch. Success in RTL simulation **does not** prove Gowin timing or real audio quality on the Tang Nano 20K.

## Windows / Gowin build

Use a new PowerShell 5.1 directory:

```powershell
git clone --branch petar/mb-doc-piano-wavetable-20261106 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-piano
```

Open `C:\AppleIIgsDev_02\a2fpga-mb-doc-piano\boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj` in Gowin.

**The HDL source deliberately inherits `AUDIO_MODE_MB_DOC=1'b1` from the fixed P3 branch.** Inspect the Gowin synthesis log for `sound_glu(MB_DOC_MODE=1'b1)`, `mb_doc_bridge`, `Mockingboard` and `mb_ay_capture` elaboration and ensure none are optimized away. Place/route, timing and bitstream should all complete. Give the new `.fs` a distinct name.

Deploy only the new **FPGA bitstream**. Leave the BL616 Stage 1 bootloader and HID-enabled Stage 2 MCU untouched; the FPGA source branch retains unrelated older MCU code. Keep Mockingboard configured in the proven slot 4.

Play the same three classical tracks and compare timbre, loudness, stereo, attack/decay and stop behavior with the preserved P3 recording. Noise explosions are still unsupported by the bridge.

To switch back, reload the previous P3 FPGA `.fs`. Do not copy this bitstream into the native Apple IIgs DOC golden release.
