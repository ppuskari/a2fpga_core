# M3 — FPGA-autonomous SD read payload staging

## Branch and safety

- **Golden M2 branch/commit:** `petar/media-m2-bidir-fat-picker-20261122`,
  `519882c551d0fb6eab2e3a02cdb7d4cea0d2447d`. IIe/ROM 3 IIgs
  directory traversal, 500+ MOD entries, J start-file, HDMI playback,
  mailbox sequencing, and MCU USB keyboard response were validated on
  physical hardware. M3 does **not** change that branch.
- **Experimental M3:** `petar/m3-sd-sector-burst-20261123`.
- **Separate IIgs 2.8MHz Mockingboard timing investigation:**
  `petar/iigs-mb-28mhz-timing-20261123`, forked at the same M2 commit.
  The title-song behavior (works at 1MHz, problematic at 2.8MHz) is
  independent of SD payload transport; do not mix speculative Mockingboard
  timing fixes into the M3 storage branch.
- M3 changes only SD **read payloads**. CMD17/CMD18, 0xFE data token
  detection, two CRC bytes, SD writes, FatFS locking/volume/partition
  logic, SSI263, AY, DOC, HDMI PCM, slot-3 media mailbox and 80-column
  ProDOS app remain on their existing paths.
- **Program FPGA volatile SRAM first; do not overwrite working M2 FPGA
  flash during validation.** MCU Stage2 is also independently flashed at
  0x40000 only after the FPGA resource/timing check.
- Passing host regressions is not physical Tang Nano 20K validation.

## New hardware contract (backwards compatible)

All existing registers and XFER spaces retain their meanings.

```
SD $6C  legacy SD_CS and slow clock                  (unchanged)
SD $6D  legacy 8-bit full-duplex TX/RX               (unchanged)
SD $6E  READ status
         bit7 1 = M3 512-byte staging capability (old M2: bit7=0)
         bit6 1 = buffer ready / completion
         bit5 1 = autonomous SD 512-byte clocking in progress
         bit4 1 = burst error (CS raised, overlapping command, etc.)
         bit0     original one-byte SD SPI busy (unchanged)
SD $6E  WRITE 0xA1 = clock in 512 bytes with MOSI=0xFF
         WRITE 0xAF = abort/reset this burst engine
XFER SPACE0, 0x800000..0x8001FF = 512-byte SD receive buffer, read only
XFER SPACE0, low legacy RAM 0x000000..0x0000FF = unchanged
XFER SPACE1 SDRAM, 2 FIFO, 3 W5100, 4/5 SSI, 6 PCM, 7 M2 = unchanged
```

The FPGA clocks SD autonomously at the existing fast SD clock setting:
54MHz / 8 = 6.75MHz. A 512-byte payload has 4096 SD clock edges,
approximately 0.61ms of pure SD serial transfer time, ignoring SD
response latency and state-machine overhead. **This is not a measured
throughput result.** The BL616 may run other tasks and use the shared
FPGA SPI port while the SD engine works. Only one FatFS disk task owns
the physical SD card, and `SD_CS` remains asserted throughout the
payload.

### SD sector read sequence

1. Disk task sends CMD17/CMD18 and polls for `0xFE` using the original
   register-byte SD path. No command-phase or write-path changes.
2. If `$6E bit7==0` or firmware flag `FPGA_SD_BURST_READ=0`, read 512
   bytes with the legacy `xchg_spi(0xFF)` loop.
3. Otherwise write `0xA1` to `$6E`; the autonomous FPGA receiver
   requests 512 back-to-back 8-bit transfers from `fpga_sd_spi`.
4. Firmware releases the shared SPI mutex between short status probes,
   and waits (RTOS sleep) for `done && !active && !error`. A bounded
   200ms timeout or error aborts the transaction and fails the sector;
   never silently returns partially clocked data or replays within an
   existing SD data packet.
5. Pull 512 bytes from XFER SPACE0 high aperture in four 128-byte
   frames, unlocking the shared SPI mutex between frames. The first
   sector compares the **entire 512B fast-portal read** against a
   conservative bytewise XFER read of the same FPGA BRAM; on mismatch,
   use the bytewise result and permanently disable *fast host SPI
   portal reads* for this boot. The autonomous FPGA SD receive engine
   remains useful independently.
6. Read the two trailing SD CRC bytes via the existing register path.
   For an M3 accelerated sector, calculate CRC16-CCITT (polynomial 0x1021,
   initial 0) over all 512 bytes and compare with the SD card's two
   big-endian wire CRC bytes. On mismatch, **reject this sector** and
   disable accelerated SD receiving for this mount; subsequent attempts
   use the original M2 bytewise SD transfer. The CRC check is independently
   selectable with `FPGA_SD_BURST_VALIDATE_CRC=0/1`, enabled by default.
   This protects SD-card-to-FPGA transfers that a local FPGA buffer
   cross-check alone cannot validate. Write/stop/multi-sector protocol
   remains FatFS/ChaN's existing logic.

Because `$6E bit0` retains its prior meaning, old MCU Stage2 also
operates with the new FPGA bitstream with no new behavior. New M3 MCU
Stage2 automatically uses old M2 bytes on an old FPGA bitstream, and
logs `M3 SD BURST FPGA=NO (M2 FALLBACK)` once.

## Gowin 1.9.9 Beta/Education headless build compatibility

The installed `gw_sh.exe` does **not** support `open_project` even
though later Gowin releases document it. An earlier M3 wrapper passed
`open_project a2n20v2_enhanced.gprj` on stdin, Gowin printed
`invalid command name "open_project"` followed by `PJ0001: No
available design files found`, yet the helper mistakenly reported an
old tracked `.fs` and old timing report as a fresh build. **That
artifact is not hardware-valid and must not be programmed.**

The corrected `Build-M3-FPGA.ps1` generates `impl/m3-headless-build.tcl`
by parsing the actual `.gprj` XML, checking every enabled source and
asset, and retaining the GUI project device, HDL source inventory,
pin/timing constraints, top module, standards, and the `prebuild.tcl`
ROM verification/timestamp hook. Its generated Tcl uses commands
available in older 1.9.9 shells:

```tcl
source {prebuild.tcl}
set_device -name {GW2AR-18C} {GW2AR-LV18QN88C8/I7}
# add_file -type verilog/vhdl/cst/sdc for every enabled source
set_option -output_base_name {a2n20v2_enhanced}
set_option -synthesis_tool gowinsynthesis
set_option -top_module {top}
set_option -verilog_std sysv2017
set_option -vhdl_std vhd1993
run all
```

The `Script` action generates this Tcl without launching Gowin.
`Build` passes it as a **script filename** to `gw_sh.exe`, captures
stdout/stderr into `impl/m3-gowin-*.log`, and **moves older `.fs` and
timing reports to a timestamped `impl/m3-previous-artifacts` archive**
before running. A nonzero exit status, Tcl error, PJ error, missing
explicit completion marker, missing newly built `.fs`, or missing
fresh timing report now fails closed. A real `run all` completion is
mandatory; mere presence of an `.fs` is not accepted.

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-media-m3
git pull --ff-only
.\Build-M3-FPGA.ps1 Script -Offline
.\Build-M3-FPGA.ps1 Build -Offline -GowinCli "C:\Gowin\Gowin_V1.9.9Beta-4_Education\IDE\bin\gw_sh.exe"
```

Do not program FPGA SRAM until the new wrapper reports a freshly built
bitstream and the Gowin place-and-route timing report has been checked.
This restores headless invocation, but does not imply real Gowin
1.9.9 synthesis was remotely run or that placement/timing closure
has yet been proven on the user's Windows installation.

### First real Gowin 1.9.9 headless synthesis/P&R failure (2026-11-23)

Initial Windows headless build successfully read and synthesized the
100 source files but P&R stopped with `PR2028` / `PR2017` on
`a2_bridge_d[5]`, `[4]`, and `[2]`: these signals use FPGA pins
that are also dedicated SSPI configuration pins. **No fresh `.fs` was
produced; do not program the FPGA.** The board pin assignments were
already validated in M2 and must NOT be moved.

Root cause: `tools/generate_m3_gowin_tcl.py` originally reconstructed
HDL files and device properties from `.gprj` but failed to reproduce
the GUI's `SSPI=true` and `MSPI=true` pin-reuse settings from
`impl/project_process_config.json`. The correct Gowin Tcl properties
are `set_option -use_sspi_as_gpio 1` and
`set_option -use_mspi_as_gpio 1`. New generation derives them from
the actual GUI config and checks that the parallel P&R process config
agrees. An absent/inconsistent setting aborts generation rather than
silently making a new pinout.

The previous wrapper also crashed while trying `$stdErr.Trim()`
because `Get-Content -Raw` returns null on an empty stderr file.
The helper now explicitly casts both log streams to strings and tests
them with `[string]::IsNullOrWhiteSpace`. If Gowin still errors, the
wrapper reports P&R failures instead of crashing or reusing an old
bitstream.

After fetching the revised M3 branch, verify the generated Tcl contains
both `-use_*spi_as_gpio 1` options before running the full build:

```powershell
git fetch origin "+refs/heads/petar/m3-sd-sector-burst-20261123:refs/remotes/origin/petar/m3-sd-sector-burst-20261123"
git merge --ff-only origin/petar/m3-sd-sector-burst-20261123
.\Build-M3-FPGA.ps1 Script -Offline
Select-String .\boards\a2n20v2-Enhanced\impl\m3-headless-build.tcl -Pattern 'use_sspi_as_gpio|use_mspi_as_gpio'
.\Build-M3-FPGA.ps1 Build -Offline -GowinCli "C:\Gowin\Gowin_V1.9.9Beta-4_Education\IDE\bin\gw_sh.exe"
```

`CI` checks actual generated Tcl/source consistency, and PowerShell
log guards. **Gowin place-and-route must still be validated in the
user's installed Windows version**, followed by timing analysis.

## Build and first hardware validation (Windows PowerShell)

Make a new worktree next to the functioning M2 checkout. Do not switch
the golden M2 working directory to the experimental branch.

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-media-m2
git fetch origin petar/m3-sd-sector-burst-20261123
git worktree add -b petar/m3-sd-sector-burst-20261123 C:\AppleIIgsDev_02\a2fpga-media-m3 origin/petar/m3-sd-sector-burst-20261123
Set-Location C:\AppleIIgsDev_02\a2fpga-media-m3
Copy-Item -LiteralPath C:\AppleIIgsDev_02\a2fpga-media-m2\boards\a2n20v2-Enhanced\hdl\piano_multisustain.mem -Destination C:\AppleIIgsDev_02\a2fpga-media-m3\boards\a2n20v2-Enhanced\hdl\piano_multisustain.mem
.\Build-M3-FPGA.ps1 Prepare
.\Build-M3-FPGA.ps1 Build
```

The `Copy-Item` line reuses your **existing verified locally extracted
SynthLAB piano data** from the M2 checkout. New Git worktrees do not carry
untracked/generated `piano_multisustain.mem` files automatically. If that
file is not present in your M2 checkout, instead supply the original
SynthLAB disk with `-SynthLABDisk` to `Build-M3-FPGA.ps1 Prepare`.
No substituted/zero-filled PCM is accepted.

If Gowin's `gw_sh.exe` is not on PATH, pass its full installed path with
`-GowinCli`. The ROM-preparation script uses the existing pinned SSI263
and Apple SynthLAB instrument assets; it must not silently insert placeholders.

Check the resulting Gowin synthesis and timing reports. Program
`boards/a2n20v2-Enhanced/impl/pnr/a2n20v2_enhanced.fs` to **FPGA SRAM**
with Gowin Programmer. Confirm the current M2 Stage2 still boots and
reads /ProTracker in legacy byte mode. This checks that M3 FPGA itself
does not perturb the working baseline while its new SD receiver is idle.

Then prepare the experimental BL616 Stage2:

```powershell
.\M3.ps1 SourceState
.\M3.ps1 Build -Jobs 8
```

Enter BL616 UPDATE/BootROM mode, then:

```powershell
.\M3.ps1 Flash
```

Enter `FLASH M3` only if the source manifest, correct branch and
binary hash checks all pass. This flashes **BL616 Stage2 at 0x40000 only**,
not signed Stage1 and not FPGA flash. Reboot normally without UPDATE,
reprogram FPGA SRAM if needed and verify MCU log:

```
M3 SD BURST FPGA=YES
M3 SD 512B BURST READY HOST SPI=BULK
```

If only `...HOST SPI=BYTEWISE FALLBACK` appears, the first-sector A/B
check rejected bulk host-SPI timing. The SD FPGA receiver remains active
but the host transfer uses conservative XFER reads automatically.

### Compare against physical M2 baseline

Before/after: browse `/ProTracker` (39 folders), `/ProTracker/1`
(~506 visible files), and `/ProTracker/2` (500 visible files).
Record existing `PICK TIMING: OPEN= READ= SORT=` diagnostics on the MCU.
Verify page 1, middle and final pages from `A2MEDIA.SYSTEM` on IIe
1MHz first, then ROM 3 IIgs at 2.8MHz; test J from the selected tenth
track, NEXT/PREVIOUS, PCM audio, USB keyboard, and SSI speech.
Repeat on a cold reboot.

For a controlled SD transport A/B, use CMake cache switches:
`FPGA_SD_BURST_READ=0` disables new SD engine at runtime in MCU
firmware even with M3 FPGA; `FPGA_SPI_SD_BURST_PORTAL_BULK=0` keeps
FPGA-autonomous SD clocking but uses conservative MCU XFER byte access.
Both need a new Stage2 build/manifest; keep M2 as a known-good baseline.

**Do not claim a measured speedup or write to FPGA flash until real
hardware sector integrity and latency checks pass.**

## Automated checks

`.github/workflows/m3-sd-burst.yml` exercises:
- Actual `fpga_sd_spi.sv` + `fpga_sd_burst.sv`, 512 synthetic SD bytes,
  4096 SD clock edges, byte-exact buffer readback, legacy byte afterward,
  CS# error and abort handling
- Independent Yosys receiver synthesis
- Real `fpga_spi.c` reading 4 × 128-byte XFER frames, byte-for-byte
  512-byte verification and an injected fast-host-SPI corruption that
  must trigger fallback
- Real `sdmm.c` with mocked FPGA registers/FatFS interfaces, including
  old FPGA capability fallback, short packet, successful 512B payload,
  CRC16-corrupted sector and sticky fallback, FPGA fault and 200ms timeout;
  no partial sectors
- Static integration guards for connector mux, $6D legacy, FPGA project
  source list, runtime capability, firmware flags and M3 branch protection

No FPGA or Stage2 silicon is emulated beyond those test models. Tang Nano
place-and-route and USB/audio contention remain physical tests.
