# J2 — MOD jukebox, paging and up to 2 MiB .MODs (hardware test candidate)

Branch: `petar/mod-jukebox-j2-largefile-20261121`; stacked on J1, not
merged. M1 is the hardware golden baseline. **Only the BL616 host Stage 2
firmware needs updating; M1 FPGA HDL and external FPGA flash are unchanged.**

## What's new
- File picker: 256-entry alphabetically sorted snapshot with 48 entries per
  page and explicit NEXT/PREVIOUS page actions. 154 files in one directory
  should now be accessible. Directory names beginning with `_` or `.`
  and names longer than 79 characters remain filtered as before.
- Jukebox: play current directory or full subdirectory tree, automatically
  advance at HxCMOD order-list wrap, next/previous, stop, manual play once
  versus repeat. 512 playlist entries max, 96 queued subdirectories max.
- MOD format: strict size/layout parsing for four-channel standard 31-sample
  ProTracker and SoundTracker 15-sample MODs. Other channel counts are
  rejected gracefully. `MOD_TOTAL_FILE_MAX = 2 MiB` (whole file).
- Only the MOD header and pattern bytes are allocated from the MCU heap,
  at most 132,156 bytes for 128 four-channel patterns. Sample waveform data
  (up to ~2 MiB minus headers/patterns) is written from SD to dedicated FPGA
  SDRAM at byte addresses 0x400000–0x5FFFFF over existing SPI XFER SPACE1.
- HxCMOD uses four separate 4-KiB, demand-filled sample caches in MCU SRAM;
  no sample access dereferences an FPGA address as a CPU pointer. The
  existing 44.1kHz / 16-bit stereo output path stays SPI SPACE6.
- On invalid files, the player reports an error and jukebox skips forward.
  The existing FIFO drain-and-advance behavior is not gapless.

## Critical safety and hardware limitations
- **Not yet proven on real FPGA SDRAM with the physical BL616.** CI's 1-MiB
  simulation checks HxCMOD PCM parity but does not verify SPI speed,
  readback reliability, memory arbitration, actual UDR, or live menu response.
- The J2 address region is **reserved for these samples**. Check for
  collisions before adding new SDRAM-backed functions (e.g. extended AUX RAM).
  Existing M1 shadow/DOC/disk/HDD mappings are below this region.
- An expensive sample-cache miss could cause a PCM FIFO underrun. Monitor
  `MCU MOD: FRAMES=... FREE=... UDR=...` under actual hardware load.
- A 2-MiB MAX is a file-size ceiling, **not support for >4-channel MODs**.
  Very large pattern-only files may still fail safely due to free MCU heap.
- Keep the **signed Sipeed Stage 1 at 0x0**, and golden FPGA flash intact.
  Do not use `make flash` or any `--stage1` flashing mode.

## Windows PowerShell 7 / native Bouffalo SDK build

Use a **new isolated checkout**, rather than cleaning/replacing M1 or J1:

```powershell
$j2 = 'C:\AppleIIgsDev_02\a2fpga-jukebox-j2'
git clone --branch petar/mod-jukebox-j2-largefile-20261121 --single-branch https://github.com/ppuskari/a2fpga_core.git $j2

$env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk'
$riscvBin = 'C:\AppleIIgsDev_02\bouffalo_tools\xuantie\xuantie-gcc-riscv-v2.10.2-windows-x86_64\bin'
$sdkMake = "$env:BL_SDK_BASE\tools\make"
$sdkCmake = "$env:BL_SDK_BASE\tools\cmake\bin"
$env:PATH = "$sdkMake;$sdkCmake;$riscvBin;$env:PATH"
Get-Command make,cmake,riscv64-unknown-elf-gcc | Select-Object Name,Source

Set-Location "$j2\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host"
make -j4 CHIP=bl616 BOARD=bl616dk
if ($LASTEXITCODE -ne 0) { throw 'J2 MCU build failed - DO NOT FLASH' }
$bin = (Resolve-Path '.\build\build_out\a2n20_bl616_host_bl616.bin').Path
Get-Item $bin | Select-Object FullName,Length,LastWriteTime
```

Only if the **new binary** was successfully produced and is the one you
intend to test:

```powershell
Set-Location "$j2\boards\a2n20v2-Enhanced\src\a2n20_bl616"
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware $bin --verify-flash
```

Reprogram the previously validated M1 FPGA bitstream to **volatile SRAM
only** after a power cycle if the FPGA has reverted to its old flash image.
The same 0xC0B0 M1 ROMless mailbox/SPACE6 PCM FPGA design is required.

## Physical test sequence

1. Confirm boot/menu/HID works **before** music selection; test the M1
   Applesoft `PRINT PEEK(49328),PEEK(49329),PEEK(49330)` = `77 66 1`.
2. Verify listing counts and page navigation with all **154 files in
   one directory**. List should show PAGE 1/4 to 4/4 (with 48 per page).
   Ensure the final page files are selectable.
3. Test your `101.mod` (172,768 B) and `u4ia.mod` (281,230 B). Both are
   standard 4-channel `M.K.` headers with sample offsets consistent with
   their actual file lengths; previous 192-KiB ceiling rejected `u4ia.mod`.
4. Test a valid ~1-MiB four-channel MOD. Confirm boot, playback and
   no UART/fatal overlay markers. If loading fails, check console logs.
5. Use `JUKEBOX: THIS FOLDER`: confirm automatic advance after one
   song order-list pass; test Next/Previous, bad-file skip, Stop.
6. Repeat with `JUKEBOX: WITH SUBFOLDERS`; test manual single-file
   Play Once/Repeat and Apple's $C0B4 commands (4–9).
7. During sustained playback verify `UDR` remains 0, and the MCU menu,
   keyboard and Telnet respond. If it freezes or UDR grows, restore the
   previously proven M1 Stage 2 MCU firmware and report latest logs.

CI includes original M1 mailbox/HDMI HDL simulation, native IIgs DOC
regression, J1 FAT jukebox scan, and J2 whole-file/SDRAM 1-MiB PCM parity.
None of these replaces real BL616 or Gowin memory timing validation.
