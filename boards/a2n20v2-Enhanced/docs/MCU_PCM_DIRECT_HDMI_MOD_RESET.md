# Direct BL616 C MOD player to HDMI — clean NTP/DOC rollback

Status: experimental end-to-end implementation. FPGA/MCU portable CI validates
the bridge and HxCMOD renderer. **Not yet synthesized in Gowin, cross-compiled
with the user's BL616 SDK or verified on physical Apple IIe/IIgs hardware.**

Repository: `ppuskari/a2fpga_core`
Branch: `petar/mcupcm-hdmi-direct-mod-clean-20261120`
Parent: `petar/sensei8-p2ac-arpeggio-pitch-fifo-20261120`.

## Scope of removal

Removed the NTP-specific decoder, C native replayer, PCM bank uploader,
timestamped DOC event queue, FPGA tracker bridge and C0nA-F tracker
mailbox; removed P2Y FPGA first-end sustain-retarget FSM and its dedicated
port from `doc5503.sv`. The August DOC oscillator **SWAP HALT then
partner START fix is still in place**.

`sound_glu.sv` now allows only established native IIgs GLU/Apple bus
registers or the working enhanced Mockingboard bridge to write DOC
registers and sound RAM; the MCU no longer arbitrates for those resources.

Retained: the original Ensoniq DOC and IIgs Sound GLU, 128K sound-RAM
extension/lock, A3 persistent Original/Enhanced/Native/Shared audio modes,
working Mockingboard AY/piano/SSI263 hybrid, BL616 speech-PCM stream on
SPI spaces 4/5, USB/SD FAT file handling, disk serving, boot priorities.

**No NTP support remains in the compiled firmware or FPGA.**
The new player accepts **standard .MOD only**; `.NTP` files must not
be selected or converted inside this firmware.

## New independent audio architecture

```text
USB/SD MOD file
  -> disk-thread FatFS broker (same safe FSOP_MOD_* handle)
  -> BL616 FreeRTOS modpcm task
  -> HxCMOD original public-domain ProTracker C decoder (44,100 Hz)
  -> interleaved signed 16-bit stereo sample frames
  -> FPGA SPI XFER SPACE 6, stream address 0 (Llo Lhi Rlo Rhi)
  -> FPGA mcu_stereo_pcm_bridge: 2048-frame FIFO
  -> HDMI 44.1 kHz sample strobe and left/right PCM
  -> post-gain HDMI saturated mix at half-level
  -> HDMI audio sample packets

Apple II native IIgs DOC (unchanged) -> Sound GLU -> HDMI
Mockingboard piano/AY/SSI263 (unchanged) -> HDL audio mixer -> HDMI
```

New PCM SPACE6 protocol:
- Read `0x800000` (16 bytes) -> `P C 01` + enabled/playing, FIFO
  level/free, underrun, overrun, frames played.
- Write `0x800000` any byte -> clear, mute FIFO and counters.
- Write `0x800001` `0x01` -> enable; `0x00` -> mute.
- Write base address `0` any multiple of 4 bytes -> interleaved
  signed PCM16LE left/right samples. No new sample header, ADSR, pitch
  or DOC firmware state.
- On starvation, output zero and count one underrun. Resume after 512
  buffered stereo frames (11.6 ms), rather than resume mid-attack.
- This transport is **not** available on P2Y/P2AA/P2AB/P2AC FPGA
  bitstreams. New FPGA compile and SRAM programming is mandatory.

HxCMOD code is sourced directly from `jfdelnero/HxCModPlayer`, with
its upstream public-domain `LICENSE` in `third_party/hxcmod`.
This is a lightweight C MOD player, not `libxmp-lite`.
A more feature-complete MOD/XM/S3M/IT decoder can later be substituted
without rewriting the HDMI transport.

Current file size cap: **192 KiB**. It depends on the available
dynamic heap and is not a promise that every file under that size will
load. This phase supports classic four-channel ProTracker MOD; don't
assume accurate multi-channel tracker playback or live looping controls.

## Windows PowerShell 5.1: paste each single command separately

### Stage 1: checkout isolated branch

```powershell
$hw = 'C:\AppleIIgsDev_02\a2fpga-mcupcm-hdmi'
if (-not (Test-Path "$hw\.git")) { git clone --branch petar/mcupcm-hdmi-direct-mod-clean-20261120 --single-branch https://github.com/ppuskari/a2fpga_core.git $hw }
git -C $hw fetch origin petar/mcupcm-hdmi-direct-mod-clean-20261120
git -C $hw switch petar/mcupcm-hdmi-direct-mod-clean-20261120
git -C $hw pull --ff-only origin petar/mcupcm-hdmi-direct-mod-clean-20261120
git -C $hw log -1 --oneline
```

### Stage 2: ensure existing piano/SSI263 ROM assets for FPGA

New PCM bridge has no ROM. The **unchanged** Enhanced DOC/Speech design
still requires the previously used ROM assets in a fresh checkout.

```powershell
Set-Location $hw
py -3 .\tools\extract_synthlab_piano.py --download
py -3 .\tools\extract_synthlab_piano.py --check
py -3 .\tools\generate_ssi263_voice.py
py -3 .\tools\generate_ssi263_voice.py --check
py -3 .\tools\generate_ssi263_p8_roms.py --check
py -3 .\tools\generate_ssi263_p9_nas_rom.py --check
py -3 .\tools\generate_ssi263_p9_output_fir.py --check
Get-Item .\boards\a2n20v2-Enhanced\hdl\piano_multisustain.mem,.\boards\a2n20v2-Enhanced\hdl\ssi263_voice.mem | Select-Object Name,Length,LastWriteTime
```

### Stage 3: compile and program FPGA **only with Gowin GUI**

Project:
`C:\AppleIIgsDev_02\a2fpga-mcupcm-hdmi\boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj`

The project includes `mcu_stereo_pcm_bridge.sv` and **no**
`sensei_tracker_bridge.sv`.
Use Gowin GUI synthesis + place/route. Program FPGA volatile **SRAM
only**, retaining the known-good golden FPGA configuration flash image.

```powershell
Get-Item "$hw\boards\a2n20v2-Enhanced\impl\pnr\a2n20v2_enhanced.fs" | Select-Object FullName,Length,LastWriteTime
Select-String -Path "$hw\boards\a2n20v2-Enhanced\impl\pnr\a2n20v2_enhanced_tr_content.html" -Pattern 'Violated|Fmax|TNS' | Select-Object -First 30
```

### Stage 4: build BL616 host application Stage 2

```powershell
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
Get-Item "$env:BL_SDK_BASE\project.build"
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host"
make -j4 CHIP=bl616 BOARD=bl616dk
if ($LASTEXITCODE -ne 0) { throw 'Direct PCM MCU build failed: do not program' }
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
Get-FileHash .\build\build_out\a2n20_bl616_host_bl616.bin -Algorithm SHA256
```

### Stage 5: program MCU Stage 2 only

```powershell
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616"
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

**Never** use `make flash` or touch signed BL616 Stage 1 at 0x00000.
Stage 2 application remains at 0x40000.

### Stage 6: hardware test

1. Cold boot with new FPGA image in SRAM and MCU Stage 2 installed.
2. Check A3 audio configuration and known-good original/native IIgs DOC
   sounds without running MOD; they must be unchanged.
3. Start the MCU menu; entry now reads **MCU MOD PLAYER**.
4. Put a known-good 4-channel `.MOD` (not `.NTP`, under 192 KiB) on
   the SD/USB FAT volume. Browse and select it.
5. Expect `MCU MOD: DIRECT HxCMOD->HDMI READY`, then
   `MCU MOD: HxCMOD ...B 44100 STEREO`, and audible stereo PCM.
6. STOP playback, verify silence and menu responsiveness.
7. Listen for gaps and check `MCU MOD: FRAMES ... FREE ... UDR ...`
   console messages. **UDR should remain zero** during steady music.
8. Change A3 audio mode; ensure the DOC and speech remain available.
9. Do not flash FPGA golden config until the independent paths are
   stable and the regression tests pass on the physical card.

Portable GCC/Icarus CI is useful but **cannot validate Gowin PNR,
BL616 firmware linking/available heap, or actual HDMI sound**.
