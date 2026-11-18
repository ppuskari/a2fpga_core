# SenseiPlay8 P2S — lossless DOC register-event scheduling

**Status:** P2S source and CI tests pass. **Not physically confirmed** on the
Apple IIe; do not replace a previous known-good persistent FPGA image before
recording 15k and Dead Waltz. Both P2R and P1D Golden worktrees are unchanged.

Repo: \`ppuskari/a2fpga_core\`
Branch: \`petar/sensei8-p2s-lossless-fifo-20261118\`
Base: \`petar/sensei8-p2-attack-sustain-20261118\`
Native ProDOS SYS remains the existing generic P2 controller in
\`ppuskari/SenseiPlay8\`, \`petar/p2-runtime-controller-20261118\`.
No special song builds, precomputed patterns or PCM conversions.

## Root cause validated by real hardware

The P2R MCU used a 64-entry FPGA FIFO with a guard of occupancy <=24,
then sent a whole tracker tick without checking its event count.
A four-channel P2R attack/sustain tick can emit 56 DOC register writes.
24+56=80 >64. The user's \`PRINT PEEK(49359)\` after 15k Boogie
returned 255: the saturating hardware overflow count. Loss of the
latter part of a multi-register note setup can produce missing notes,
wrong WTP/RTS, incorrect pitch, missing retriggers and stereo imbalance.

## Implementation

- Dedicated BL616 staging ring of 256 timestamped DOC register events;
  the ProTracker C engine generates **one real-time tick** into the ring.
- At most 64 events are generated per tick. Tick execution is delayed
  until enough space exists to stage the whole tick without memory loss.
  (This is memory pressure/backpressure, not ProTracker event precomputation.)
- The MCU reads **actual FPGA FIFO occupancy** from SPI6 offset \`0x06\`,
  then submits at most \`64 - occupancy\` events. FIFO entries execute at
  their original timestamps and in original order. The MCU is the sole
  event producer, so concurrent consumption only creates more free slots.
- 160-ms look-ahead allows several ticks to be queued ahead where there
  is capacity, reducing audio jitter from the FAT/USB host and FreeRTOS.
- On STOP, existing pending FPGA events and MCU staged events are both
  discarded intentionally, then eight physical DOC oscillators are
  silenced and ownership is released. That is the expected STOP behavior,
  **not** an uncontrolled dropped note.
- Completion waits until both the MCU queue and FPGA FIFO are empty;
  thus the final notes aren't discarded when the MOD row interpreter
  reaches the end of the order table.
- The FPGA exposes per-song reset (SPI6 write \`0x17=0xA5\`), FIFO
  capacity (\`0x27\`), FIFO high-water (\`0x28\`) and late-event count
  (\`0x29-0x2A\`). Existing $C0CF PEEK overflow remains valid.
- At STOP and song completion, the BL616 OSD console reports
  \`FPGA OVR/HIGH/LATE\` and \`MCU SENT/HIGH/LATE/MAXMS\`.
  Zero overflow is the minimum acceptance criterion. Positive
  late-event counts indicate insufficient scheduling headroom, even
  if no events were dropped.

The original SynthLab piano, SSI263 speech, DOC sample attack/sustain,
MOD parser, FAT32 SD picker and original generic ProDOS SYS are unchanged.

## Windows PowerShell 5.1 — paste each command separately

### 1. Isolated checkout

\`\`\`powershell
$hw = 'C:\AppleIIgsDev_02\a2fpga-sensei-p2s'
if (-not (Test-Path "$hw\.git")) { git clone --branch petar/sensei8-p2s-lossless-fifo-20261118 --single-branch https://github.com/ppuskari/a2fpga_core.git $hw }
git -C $hw fetch origin petar/sensei8-p2s-lossless-fifo-20261118
git -C $hw switch petar/sensei8-p2s-lossless-fifo-20261118
git -C $hw pull --ff-only origin petar/sensei8-p2s-lossless-fifo-20261118
git -C $hw log -1 --oneline
\`\`\`

### 2. Generate all audio ROM assets

\`\`\`powershell
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2s
py -3 tools\extract_synthlab_piano.py --download
py -3 tools\extract_synthlab_piano.py --check
py -3 tools\generate_ssi263_voice.py
py -3 tools\generate_ssi263_voice.py --check
py -3 tools\generate_ssi263_p8_roms.py --check
py -3 tools\generate_ssi263_p9_nas_rom.py --check
py -3 tools\generate_ssi263_p9_output_fir.py --check
(Get-Content .\boards\a2n20v2-Enhanced\hdl\piano_multisustain.mem | Measure-Object -Line).Lines
(Get-Content .\boards\a2n20v2-Enhanced\hdl\ssi263_voice.mem | Measure-Object -Line).Lines
\`\`\`

Expect 1408 piano words, 8192 voice entries; piano FNV32=170BB8B3.
The hybrid SSI263 uses the existing checked-in Pico-derived C DSP.

### 3. Gowin FPGA complete rebuild

\`\`\`powershell
$gw = (Get-Command gw_sh.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if (-not $gw) { $gw = Get-ChildItem 'C:\Gowin' -Filter gw_sh.exe -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }; if (-not $gw) { throw 'Gowin gw_sh.exe not found' }
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2s\boards\a2n20v2-Enhanced
@('open_project a2n20v2_enhanced.gprj','run all','exit') | & $gw
Get-Item .\impl\pnr\a2n20v2_enhanced.fs | Select-Object FullName,Length,LastWriteTime
Select-String -Path .\impl\pnr\a2n20v2_enhanced_tr_content.html -Pattern 'Violated|Fmax|TNS' | Select-Object -First 30
\`\`\`

Verify fresh timestamp, zero timing violations and clock constraints.

### 4. Build BL616 Stage 2 host firmware

Bouffalo SDK v2.3.27 and T-Head RISC-V GCC/Make already required.

\`\`\`powershell
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
Get-Item "$env:BL_SDK_BASE\project.build"
git -C $env:BL_SDK_BASE describe --tags
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2s\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
make -j4 CHIP=bl616 BOARD=bl616dk
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
Get-FileHash .\build\build_out\a2n20_bl616_host_bl616.bin -Algorithm SHA256
\`\`\`

### 5. Generic ProDOS SYS: same as working P2/P2R

**No new .po required**; continue using your currently working
\`SenseiPlay8-P2-RuntimeMOD-ProDOS243.po\` with \`SENSEI8.SYSTEM\`.
If building the generic 6502 client from source:

\`\`\`powershell
$ii = 'C:\AppleIIgsDev_02\SenseiPlay8-P2'
if (-not (Test-Path "$ii\.git")) { git clone --branch petar/p2-runtime-controller-20261118 --single-branch https://github.com/ppuskari/SenseiPlay8.git $ii }
git -C $ii fetch origin petar/p2-runtime-controller-20261118
git -C $ii switch petar/p2-runtime-controller-20261118
git -C $ii pull --ff-only origin petar/p2-runtime-controller-20261118
cd C:\AppleIIgsDev_02\SenseiPlay8-P2
py -3 tools\make_p2_runtime_sys.py
py -3 tests\test_p2_runtime_sys.py
Get-Item .\dist\SENSEI8-P2.SYSTEM | Select-Object FullName,Length,LastWriteTime
\`\`\`

### 6. Hardware update — protect Stage 1 and Golden FPGA

Only after both builds succeed. For initial test, FPGA **volatile SRAM**
programming (no -f), then BL616 Stage 2 offset 0x40000 **only**.

\`\`\`powershell
Get-Command openFPGALoader -ErrorAction Stop
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2s\boards\a2n20v2-Enhanced
openFPGALoader -b tangnano20k .\impl\pnr\a2n20v2_enhanced.fs
py -3 -m pip install bflb-iot-tool pyserial
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2s\boards\a2n20v2-Enhanced\src\a2n20_bl616
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
\`\`\`

Re-load FPGA SRAM if a power cycle was needed during MCU flashing:

\`\`\`powershell
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2s\boards\a2n20v2-Enhanced
openFPGALoader -b tangnano20k .\impl\pnr\a2n20v2_enhanced.fs
\`\`\`

**Never \`make flash\`**: it can overwrite fused BL616 signed Stage 1
at 0x0. Make the FPGA flash persistent only after physical audio
verification, using \`openFPGALoader -b tangnano20k -f ...\`.

### 7. Acceptance test

Keep the already working FAT32 SD card \`MODS\` folder and ProDOS boot
image. The firmware's MCU HDMI menu is still the file picker.

1. Set STORAGE SOURCE SD ONLY, RESCAN / REMOUNT ALL if needed.
2. Native DOC mode slot 4. Launch \`SENSEI8.SYSTEM\` from Bitsy Bye.
3. TAB HDMI USB keyboard -> MOD LIBRARY -> select \`15k.mod\`.
4. Record HDMI stereo. After song ends, enter Applesoft and run
   \`PRINT PEEK(49359)\` for virtual slot 4 $C0CF. **Target: 0**.
5. Check the BL616 OSD log for P2S FPGA \`OVR=0\`, FIFO high-water and
   late-event counters, as well as MCU \`LATE/MAXMS\`.
6. Select Dead Waltz, then another compatible 4-channel .MOD. STOP and
   reselect repeatedly, verifying no residual sustain and no reboot.
7. Compare note starts, stereo levels and tempo to the existing VLC
   reference. Zero overflow does not by itself prove exact tracker
   timing or sample fidelity.

Existing limitations: four-channel classic MOD; <=64 KiB source file,
<=49,152 bytes DOC sample bank, <=8 KiB individual DOC waveform,
non-power-of-two sustain loops approximated by repeating source PCM.
Future high-resolution software mixer remains a separate backend.
