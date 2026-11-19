# SenseiPlay8 P2T — One controlled fidelity pass, then NTP or PCM mixer

Branch: \`petar/sensei8-p2t-panning-pitch-20261118\`
Base: \`petar/sensei8-p2s-lossless-fifo-20261118\`
Status: **source and portable regressions passed; physical playback unverified**.

P2S physical findings: 8,249 MCU DOC register events, FPGA overflow 0,
FPGA FIFO high-water 64, FPGA late dispatch 0; music was still wrong.
Unrelated P10 speech rate/CPU/SPI counters read zero while speech idle.

## P2T changes (MCU only)

1. Correct MOD channels 0/3 -> actual DOC **LEFT** assignment bit 4,
   MOD channels 1/2 -> DOC **RIGHT** bit clear. The FPGA DOC mixer
   explicitly sends \`curr_ca_w[0]\` to left and zero to right. Previous
   P2S logic inverted that mapping.
2. Recover base DOC frequency at ProTracker row tick zero when a preceding
   row used arpeggio (0xy) or vibrato (4xy/6xy) and the new row has no
   normal retrigger. Without this, tick 5 of a 0xy effect can leave the
   previous raised semitone playing indefinitely.
3. New synthetic source-level regression verifies all four channels'
   two-oscillator stereo assignment, base frequency restoration, no
   surprise retrigger on a blank row, and compatibility with prior P2R/P2S.
4. Existing hardware FIFO and PCM upload logic are **unchanged**.

There is **no FPGA HDL change**, so users already running the P2S FPGA
bitstream only need to rebuild and flash the P2T BL616 Stage 2 application.

## Key architecture decision

The Apple IIe SYS is **optional** for the MCU menu workflow.
\`menu.c\` calls \`sensei_runtime_choose()\`, which sends the chosen FAT32
MOD path to the BL616 tracker; \`sensei_tracker_task\` loads the file,
transfers the DOC sample bank, claims DOC owner and starts playback.
The menu also submits STOP. The Apple IIe \`SENSEI8.SYSTEM\` only provides
an optional host-side launcher/STOP and an easy way to test the slot
personality. Test with no Apple IIe application launched.

## Hardware validation and pivot gate

- Use the same native DOC audio mode, same FAT32 SD card and same
  \`15k.mod\`, plus the untouched VLC reference.
- From MCU console: \`STORAGE -> SD ONLY -> RESCAN/REMOUNT\`,
  \`MOD LIBRARY -> BROWSE .MOD FILES -> MODS\`.
- Test **without** running the Apple IIe SYS first.
- Record HDMI stereo and compare channel correspondence, note pitches and
  effects. Keep \`FPGA OVR=0\`; inspect \`MCU LATE\` after SONG DONE.
- If P2T still has major errors, **stop broad ProTracker-to-DOC patches**.
  Next deliberate experimental pass is NTP as a DOC-native format. Work
  from NinjaTrackerPlus's real NTP engine/parser and a legal source NTP,
  rather than guessing the format.
- If NTP still fails or fidelity is inadequate, port a proven tracker
  replay **engine** (not MilkyTracker's GUI). Candidates:
  MilkyTracker's BSD-licensed MilkyPlay, or MIT libxmp-lite (C). The engine
  should render PCM on BL616; FPGA gains a dedicated **stereo** PCM FIFO
  feeding the HDMI mixer. Existing SSI263 PCM transport is mono and
  shared with speech, so it must not simply be overwritten.
- Before deciding the MCU can afford a 22.05/44.1 kHz mixer, measure free
  heap after USB/SD mounts, task stack usage, end-to-end SPI throughput,
  and sustained 4-channel integer-mix CPU cost. Never assume free RAM or
  44.1 kHz service capacity just from nominal BL616 clock speed.

## PowerShell 5.1: one separate command per paste

### 1. Isolated checkout (preserves P2S Golden)

\`\`\`powershell
$hw = 'C:\AppleIIgsDev_02\a2fpga-sensei-p2t'
if (-not (Test-Path "$hw\.git")) { git clone --branch petar/sensei8-p2t-panning-pitch-20261118 --single-branch https://github.com/ppuskari/a2fpga_core.git $hw }
git -C $hw fetch origin petar/sensei8-p2t-panning-pitch-20261118
git -C $hw switch petar/sensei8-p2t-panning-pitch-20261118
git -C $hw pull --ff-only origin petar/sensei8-p2t-panning-pitch-20261118
git -C $hw log -1 --oneline
\`\`\`

### 2. BL616 MCU toolchain and Stage 2 compile (required)

\`\`\`powershell
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
Get-Item "$env:BL_SDK_BASE\project.build"
git -C $env:BL_SDK_BASE describe --tags
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2t\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
make -j4 CHIP=bl616 BOARD=bl616dk
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
Get-FileHash .\build\build_out\a2n20_bl616_host_bl616.bin -Algorithm SHA256
\`\`\`

### 3. Existing P2S FPGA image — no rebuild needed

Since P2T contains **zero FPGA HDL modifications**, retain the working
P2S SRAM/flash bitstream. If it was lost due to a board reset, use the
P2S bitstream that already worked, or rebuild from this branch using the
same SynthLab/SSI263 generator and Gowin commands from the P2S guide.

To generate audio assets if making a fresh optional FPGA rebuild:

\`\`\`powershell
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2t
py -3 tools\extract_synthlab_piano.py --download
py -3 tools\extract_synthlab_piano.py --check
py -3 tools\generate_ssi263_voice.py
py -3 tools\generate_ssi263_voice.py --check
py -3 tools\generate_ssi263_p8_roms.py --check
py -3 tools\generate_ssi263_p9_nas_rom.py --check
py -3 tools\generate_ssi263_p9_output_fir.py --check
\`\`\`

Optional full Gowin rebuild:

\`\`\`powershell
$gw = (Get-Command gw_sh.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if (-not $gw) { $gw = Get-ChildItem 'C:\Gowin' -Filter gw_sh.exe -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }; if (-not $gw) { throw 'Gowin gw_sh.exe not found' }
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2t\boards\a2n20v2-Enhanced
@('open_project a2n20v2_enhanced.gprj','run all','exit') | & $gw
Get-Item .\impl\pnr\a2n20v2_enhanced.fs | Select-Object FullName,Length,LastWriteTime
Select-String -Path .\impl\pnr\a2n20v2_enhanced_tr_content.html -Pattern 'Violated|Fmax|TNS' | Select-Object -First 30
\`\`\`

Only if you built a new bitstream, program first to **volatile SRAM**
without the \`-f\` flag:

\`\`\`powershell
openFPGALoader -b tangnano20k .\impl\pnr\a2n20v2_enhanced.fs
\`\`\`

### 4. Flash MCU Stage 2 ONLY and verify

\`\`\`powershell
py -3 -m pip install bflb-iot-tool pyserial
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2t\boards\a2n20v2-Enhanced\src\a2n20_bl616
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
\`\`\`

If the MCU firmware update resets/power-cycles the FPGA, reload your
existing working P2S bitstream into volatile SRAM using the correct
P2S build path. DO NOT flash a mismatched old FPGA that lacks P2S.

**Never run \`make flash\`, which could replace the fused BL616 signed
Stage 1 at 0x0.** Only Stage 2 at 0x40000 is safe for this app.

### 5. ProDOS disk (optional)

The existing generic \`SenseiPlay8-P2-RuntimeMOD-ProDOS243.po\` still
works with the P2T MCU. For a standalone experiment, do **not** launch
\`SENSEI8.SYSTEM\`; directly use the MCU menu to select the song.

### 6. Accept/reject this branch

1. Use 15k and Dead Waltz from FAT32 SD with Native DOC selected.
2. Hear whether stereo instrumentation and effect pitch recover.
3. Record same starting point and compare to VLC.
4. Confirm PEEK(49359)=0 and P2S FPGA OVR=0 after playback.
5. Either preserve P2T as an incremental improvement or move to NTP.
