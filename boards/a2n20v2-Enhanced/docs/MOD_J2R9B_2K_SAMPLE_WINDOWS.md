# J2R9B: four 2KiB sample windows per voice, PCM-only bulk SPI

## Motivation (real FPGA hardware)

The J2R9A full SDRAM bytewise / PCM512 trial recovered the pattern
readback corruption caused by J2R9's aggressive SDRAM bursts. The
large 4CH MOD plays with UDR stable at ~1, but original 8CH 3EDGES.mod
still has audible interruptions. The photographed 8CH readings were:

- 48 patterns and 98,304 bytes staged; no FPGA pattern faults (E=0)
  and no PCM sample bounds faults (ERR=0).
- UDR rose from 1 to 29 during the same playback.
- RMAX was 67,546us for a 256-frame HxCMOD rendering block.
- DMIS reached 7 sample cache misses in one block.
- SMAX climbed from ~647us up to 15,581us; bulk PCM is helpful but
  is not enough to mask worst-case SDRAM sample read cost.
- LOW reached 219 frames. At 44.1kHz, one 256-frame block is 5.8ms
  and the whole 2048-frame PCM FIFO holds only ~46.4ms.

The 8KiB per-voice sample caches in J2R9A each fill in a single
blocking 8KiB SDRAM read. Seven misses might transfer up to 56KiB
in one rendering block. Those reads use the safe-but-slow bytewise SPI
path. A single RMAX can exceed the FPGA's total buffered audio.

## J2R9B experiment

- **Keep exactly eight voices x 8192 bytes of MCU PCM sample payload**.
  No SRAM capacity is discarded.
- Divide each 8KiB per-voice cache into **four 2048-byte independently
  cached subpages**, chosen by bounded local LRU metadata.
- A cache hit requires zero FPGA traffic; each *miss* now reads at most
  2048 bytes rather than 8192 bytes. The same four 2KiB subpages can
  be retained simultaneously in MCU SRAM.
- Preserve the exact 16KiB shared MOD pattern cache, the separate
  2MiB FPGA sample bank at 0x400000, 256KiB FPGA pattern bank
  at 0x600000, and HxCMOD playback/mixing/gain pipeline.
- Preserve J2R9A **bytewise SDRAM read AND write** transport.
  Do not enable unsafe full-bulk FPGA SDRAM transfers.
- Preserve J2R9A targeted **PCM512 HDMI SPI bulk writes**, with
  existing mutex and 20MHz Mode1 interface.
- Handle the old in-place MOD invert-loop write by updating every
  resident voice/subpage holding the changed byte.
- Retain MIS, ERR, RMAX, SMAX, DMIS, LOW, PF, PH and EV diagnostic
  counters. `PG` now measures actual fetch size, not SRAM capacity.
- Three host-compiled cache configurations have regression tests:
  2048 (target), 4096 and 8192 bytes per miss, while retaining 8192B
  per voice. CMake cache option `MOD_STORE_FETCH_BYTES` selects them.

Expected OSD after an actual MOD load:

    MOD MCU CACHE=16384B
    MOD SMP CACHE=8x8192B
    MOD SMP WIN=4x2048B
    MOD SPI=PCM512 SDRAM=BYTE

The exact 4x2048B string is compiled into the target firmware and
checked by the guarded Stage2 PowerShell wrapper before flashing.

**Tradeoff:** smaller 2KiB pages may increase MIS because of page
turnover. Do not interpret a higher miss count alone as a regression.
Measure actual `SMP SPI B` (total transferred sample bytes),
`RMAX` (worst render latency), `LOW` (FIFO low water), UDR
growth and how the music sounds. Fewer worst-case blocking bytes is a
hypothesis, not a guaranteed real-time fix.

## Windows PowerShell — clone, build, Stage2 only

Use an isolated checkout: DO NOT overwrite J2R9A or the proven J2R8
Stage2 rollback binary.

~~~powershell
$j2r9b="C:\AppleIIgsDev_02\a2fpga-jukebox-j2r9b"; git clone --single-branch --branch petar/mod-j2r9b-2k-sample-subpages-20261122 https://github.com/ppuskari/a2fpga_core.git $j2r9b; if($LASTEXITCODE -ne 0){throw "J2R9B clone failed"}
~~~

Build automatically using the neighboring Bouffalo SDK and Xuantie GCC
toolchain. The helper validates the Git HEAD, local changes, SHA256 of
the firmware and compiled sample-window signature.

~~~powershell
Set-Location $j2r9b; .\J2R9B.ps1 Build
~~~

If and only if the native build succeeds, enter BL616 UPDATE/BootROM
mode and explicitly program **MCU Stage2 at 0x40000 only**:

~~~powershell
.\J2R9B.ps1 Flash
~~~

The flash script requires typed confirmation and leaves Sipeed Stage1,
FPGA flash, and saved A3 audio mode settings alone. It reports an actual
write result, not a claim of byte-for-byte readback. Stage1 can briefly
enumerate as PARTIAL before it chain-loads Stage2.

Reconnect normally (no UPDATE) and optionally check runtime USB:

~~~powershell
.\J2R9B.ps1 CheckRuntime
~~~

For detailed help: `.\J2R9B.ps1 Help`.

## Hardware test matrix

1. Same large 4CH MOD from J2R9A: verify actual playback and stable
   UDR (previously 1). Confirm both pattern/sample integrity faults
   remain zero and the four-line J2R9B signature above.
2. 3EDGES.mod 48-pattern 8CH: compare UDR *rate* to the same elapsed
   frames on J2R9A (UDR 29 and RMAX ~67,546us at ~2.36M frames).
   Compare RMAX, SMAX, DMIS, LOW, and SMP SPI B. Expect fewer peak
   bytes per individual cache miss, but not necessarily fewer misses.
3. A_clown_in_the_moon 8CH and cheer.mod 8CH: listen for the heavy
   percussion dropouts; record cumulative UDR and elapsed frames.
4. Stop if FPGA pattern readback fails, a sample is corrupt, a song
   stops unexpectedly or voice playback is distorted. Restore the
   saved J2R9A or J2R8 **Stage2 only**, never Stage1 or FPGA flash.

This remains an **untested native BL616 build and hardware experiment**
until physically compiled and loaded. GitHub C host tests validate
cache data/eviction/write coherence and HxCMOD PCM parity but cannot
guarantee timing or BL616 SPI hardware behavior.
