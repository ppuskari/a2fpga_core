# P9M — Apple IIe-only SSI-263/DOC speech development FPGA

**Purpose:** Free real Gowin logic by removing unused enhanced/IIgs graphics
from the P9L test bitstream, not by degrading SSI-263 sound synthesis.

**Source branch:** `petar/ssi263-p9l-resource-opt-20261109`

**Build branch:** `petar/ssi263-p9m-iie-speech-trim-20261109`

## Input hardware report

The user's latest Gowin run on P9L ended:
```
ERROR (RP0006) : The number(23147(15025 LUTs, 7768 ALUs,
24 ROM16s, 55 SSRAMs)) of logic in the design exceeds
the resource limit(20736) of current device
```

P9L is **2,411 resource units above** the limit (~11.6%). P9 was
23,140, so the arithmetic replacement shifted resources rather than
reducing total resource consumption.

Do not claim a resource saving until Gowin synthesizes **this** P9M
branch; GitHub Icarus/Verilator only verify SSI speech behavior.

## Compile-time feature surgery

Top: `boards/a2n20v2-Enhanced/hdl/top.sv`

### Trim IIgs VGC/SHR output

- New `IIE_SPEECH_VIDEO_TRIM=1'b1` default.
- Preserve the SDRAM-backed `apple_video_gen`, original
  `direct_display`, 27 MHz HDMI output, raster CDC and border
  generator used for Apple IIe text / 80-column / lores / hires.
- Do not elaborate `vgc_gen`, the second 640 x 400
  `direct_display`, its SHRG_MODE mux or the VGC read pipeline.
- Set `apple_memory_sdram.VGC_MEMORY=0`, removing the 32 KB
  SHR extension while retaining the 16 KB enhanced IIe auxiliary
  video memory needed for 80-column and double-hires output.
- Restoring `IIE_SPEECH_VIDEO_TRIM=0` reinstates the original
  Enhanced IIgs Super Hi-Res path.

**This build is not intended for native IIgs Super Hi-Res testing.**

### Eliminate disabled SuperSprite hardware at elaboration

- `SUPERSPRITE_ENABLE=0` was already the P9L default, but the F18A
  video processor still appeared as an instantiated source through
  its compositing and scanline outputs.
- P9M wraps the whole SuperSprite instance in a generate condition
  and drives original Apple RGB directly to the HDMI overlay when
  disabled, passing through the scanline switch.
- Stubs read/IRQ/PSG outputs appropriately. The real SuperSprite
  is restored by `SUPERSPRITE_ENABLE=1`.

**A module in Gowin's parser log is not proof it used LUTs.**
Even in this optimized project F18A/VGC source files may still be
listed and parsed because the Gowin project retains them for alternate
configurations. Only the final mapped count validates savings.

### Preserved

- Both Mockingboard AY chips, both VIAs, SSI-263 slot/controller,
  CA1 interrupt signaling and the new complete-chip 5-stage DSP.
- 256 NAS/F2 coefficient pairs, glottal ROM, noise shaping and
  193-tap serial output reconstruction.
- Existing Ensoniq DOC 7-zone piano, AY/DOC bridge,
  full HDMI audio gain/limiter, BL616 SPI / MCU/SD, Apple II bus.
- `MOCKINGBOARD_SSI263_FULL_CHIP_ENABLE=1`.
- `MB_SPEECH_GAIN_NUM=1` for P9 experimental listening.
  Revert to 0 to mute speech and isolate clean piano.
- The debug overlay and normal Apple IIe video diagnostics.

### Already disabled in P9L

Super Serial, Disk II, Uthernet II, HDD, standalone Apple speaker,
and scanlines are already defaulted off. Do not expect additional
savings from merely repeating their existing flag settings.
The BL616 interface and SDRAM controller MUST be preserved.

## Single-line Windows PowerShell 5.1

```powershell
git clone --branch petar/ssi263-p9m-iie-speech-trim-20261109 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p9m
```
```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p9m
```
```powershell
py -3 tools\extract_synthlab_piano.py --download
```
```powershell
py -3 tools\generate_ssi263_voice.py
```
```powershell
py -3 tools\generate_ssi263_p8_roms.py --check
```
```powershell
py -3 tools\generate_ssi263_p9_nas_rom.py --check
```
```powershell
py -3 tools\generate_ssi263_p9_output_fir.py --check
```
```powershell
Start-Process .\boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj
```

Check Gowin synthesis RP0006 **before** placement/route. The target
limit is 20,736; leave practical margin if possible. Do not flash
until synthesis, place/route, timing and proper signal assignments pass.

## Follow-up if still above budget

Do **not** remove DOC multisample piano or the SSI-263 output FIR first.
Next place to investigate is the optional `DebugOverlay` and other
HDMI-only instrumentation, but preserve the current debug display
until its cost is actually measured. An additional dedicated
speech-only bitstream could disable unused rendering features.

The tested P6 clean-music bitstream is the fallback for any
unexpected audio failure. P9/P9L/P9M are experimental speech engines
whose waveform parity with the native SSI263 reference is still
incomplete.
