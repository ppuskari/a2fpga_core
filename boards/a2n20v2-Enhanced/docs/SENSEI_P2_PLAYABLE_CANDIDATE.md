# SenseiPlay8 P2 — Runtime MOD hardware release candidate

2026-11-18. **CI-verified, physical hardware test pending.** This is a development branch, not the Golden audio firmware. Preserve your existing FPGA/MCU binaries and do not overwrite secure BL616 Stage 1.

## Architecture and user workflow

- A generic ProDOS SENSEI8.SYSTEM runs on a stock Apple IIe. There are no compiled-in songs, converted MOD files or precomputed effect streams.
- TAB on the HDMI USB keyboard opens the existing BL616 MCU on-screen menu; MOD LIBRARY uses its real FAT USB/SD directory/file picker, including subdirectories and .MOD filtering.
- Selected original four-channel, 31-instrument ProTracker MOD files are loaded at runtime by the BL616 FAT broker, into MCU memory. No custom PC conversion is needed.
- The BL616 C tracker interprets the original pattern/order flow and pitch/volume effects live. FPGA SPI6 schedules timed DOC writes at millisecond precision.
- PCM sample conversion happens on the BL616 after opening each file. The FPGA receives 32-bit aligned DOC Sound-RAM words, holds GLU SDRAM ownership and acknowledges each actual memory write before the next begins.
- STOP in MOD LIBRARY returns to song selection. ESC on the Apple IIe client sends STOP and quits to ProDOS. The native Apple IIe *screen* directory picker remains future work; the first candidate uses the MCU HDMI OSD.

## PCM SDRAM handshake (SPI XFER SPACE 6)

| Offset | Access | Meaning |
|---|---|---|
| 0x18–0x19 | W | Little-endian word address, 0..16383 |
| 0x1A–0x1D | W | DOC PCM bytes in memory byte-lane order |
| 0x1E | W | Commit with 0xA5 |
| 0x1F | W | BEGIN 0xA5, END 0x5A, ABORT 0 |
| 0x20 | R | bit0 active, bit1 pending, bit2 error, bit3 complete |
| 0x21–0x22 | R | 16-bit acknowledged word counter |
| 0x23 | R | error code (zero on success) |
| 0x26 | R | P2 capability 0x42 |

PCM uploading is restricted to Native/Shared DOC audio mode. The uploader refuses to start if the capability is absent, a prior write is unacknowledged, memory ownership is unavailable, an error is signaled, or the requested bank exceeds 64 KiB. Native 128 KiB expansion and software mixing are later improvements.

## Hardware tests: user-owned originals on FAT storage

Put the MOD files in e.g. MODS/15k.mod and MODS/1_minute_dead_waltz.mod on a **FAT-formatted USB/SD volume accessible to the BL616**. These are NOT files inside the ProDOS .po disk image.

- 15k Boogie: 6 orders, 384 rows, 10,496 DOC PCM bytes / 2,624 acknowledged words; approximately 65 sec.
- 1 Minute Dead Waltz: 15 orders, 424 executed rows, 8,192 DOC PCM bytes / 2,048 acknowledged words; approximately 60 sec.
- Both recordings should have zero FIFO overflows and PCM errors, reasonable levels, correct L/R output, and no missed notes; STOP/reselect and ESC cleanup must work.

## Windows PowerShell 5.1 build: each line pasted separately

```powershell
git clone --branch petar/sensei8-p2-playable-20261118 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-sensei-p2
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2
py -3 tools\extract_synthlab_piano.py --download
py -3 tools\extract_synthlab_piano.py --check
py -3 tools\generate_ssi263_voice.py
py -3 tools\generate_ssi263_voice.py --check
py -3 tools\generate_ssi263_p8_roms.py --check
py -3 tools\generate_ssi263_p9_nas_rom.py --check
py -3 tools\generate_ssi263_p9_output_fir.py --check
```

FPGA: adjust C:\Gowin if installed elsewhere and verify bitstream timestamp and timing reports.

```powershell
$gw = (Get-Command gw_sh.exe -ErrorAction SilentlyContinue).Source
if (-not $gw) { $gw = Get-ChildItem 'C:\Gowin' -Filter gw_sh.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }; if (-not $gw) { throw 'Gowin gw_sh.exe missing' }
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2\boards\a2n20v2-Enhanced
@('open_project a2n20v2_enhanced.gprj','run all','exit') | & $gw
Get-Item .\impl\pnr\a2n20v2_enhanced.fs | Select-Object FullName,Length,LastWriteTime
Select-String -Path .\impl\pnr\a2n20v2_enhanced_tr_content.html -Pattern 'Violated|Fmax|TNS' | Select-Object -First 30
```

MCU: Bouffalo SDK v2.3.27 must already be installed and BL_SDK_BASE set; GNU Make and T-Head RISC-V compiler on PATH.

```powershell
cd C:\AppleIIgsDev_02\a2fpga-sensei-p2\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
make -j4 CHIP=bl616 BOARD=bl616dk
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
```

The secure-boot BL616 should be updated **only in Stage 2 at 0x40000** through the a2n20-mcu-program utility, after verifying both the MCU and FPGA builds. Do NOT run a generic SDK make flash that may overwrite signed Stage 1 at 0x0. First try volatile SRAM FPGA programming if possible.

Generic ProDOS controller in the companion SenseiPlay8 repo:

```powershell
git clone --branch petar/p2-runtime-controller-20261118 --single-branch https://github.com/ppuskari/SenseiPlay8.git C:\AppleIIgsDev_02\SenseiPlay8-P2
cd C:\AppleIIgsDev_02\SenseiPlay8-P2
py -3 tools\make_p2_runtime_sys.py
py -3 tests\test_p2_runtime_sys.py
```

Output: dist\SENSEI8-P2.SYSTEM (ProDOS SYS file type FF, load $2000). A ready-to-boot .po image was generated from the user's original ProDOS 2.4.3/Bitsy Bye disk in the conversation, preserving all 20 original files.

## Validation boundary

Passed CI: FPGA PCM staging, byte order, SDRAM-ready acknowledgment and exclusive owner logic; BL616 uploader success/failure tests; live MOD parser, filesystem requests, 6502 launcher, 15k/Waltz format/memory audit, synthetic tracker timing, P1D backward compatibility.

**Not yet passed:** full Gowin synthesis/place-and-route timing on the actual board, Bouffalo SDK Stage 2 linked build, physical PCM upload and real MOD HDMI playback. Keep this branch in release-candidate status until two physical recordings pass. The proven P1D and P1B/P1C hardware files remain unchanged.
