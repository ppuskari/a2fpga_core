# J2R8 — 16-KiB pattern cache, 8 x 8-KiB samples, adaptive PCM refill

Hardware test candidate. **BL616 MCU Stage2 only.** There is **no FPGA HDL
change** and no change to Stage1, FPGA flash, Apple II DOC, Mockingboard,
Ensoniq native routing or PCM postmix gain.

## Why this experiment

- J2R6 first played original 48-pattern 8-channel `3EDGES.mod` where J2R4
  failed to allocate a 99,388-byte contiguous MCU pattern block.
- The J2R6 live pattern cache correctly reported `PF=29 B=59392` (29 x 2048).
- J2R6 `3EDGES` PCM underrun count rose 4→7→10 while sample-cache
  misses reached 10,227; page and sample invalid-read faults were zero.
- J2R6 `A_clown_in_the_moon` reached `UDR=43 MIS=6374` with audible
  failures in dense drum sections; J2R6 four-channel MODs had UDR=0.
- Another eight-channel module, `cheer.mod`, produces heavy audible dropouts
  during its busiest drum sections. The user has the original MOD; it is not
  currently committed to the repository and isn't a host CI fixture.

## Memory changes

| Resource | J2R7 | J2R8 default |
| --- | ---: | ---: |
| Shared HxCMOD pattern LRU | 8,192B | **16,384B** |
| Per-voice PCM sample cache | 8 x 4,096B = 32,768B | **8 x 8,192B = 65,536B** |
| Total static cache payload | 40,960B | **81,920B** |
| Sequential FAT stage buffer | 4,096B | 4,096B |
| FPGA sample bank | 0x400000..0x5FFFFF | unchanged |
| FPGA pattern bank | 0x600000..0x63FFFF | unchanged |

The LRU uses sixteen 1-KiB slots, fitting 16 x 4CH patterns or 8 x
6/8CH patterns (6CH occupies 2KiB including slack).

Larger pages are a **trade-off**, not a free performance gain: they
may produce fewer page misses but each miss holds the shared SPI mutex for
up to 8KiB of data. For controlled source builds, `MOD_STORE_PAGE=4096u`
restores the former sample-cache size; CI executes PCM parity in both sizes.

## Real-time scheduling and measurements

- Remove mandatory 2ms delay when substantial FIFO space is available:
  the PCM render task cooperatively yields rather than sleeping if at least
  3 x 256-frame blocks were free before rendering one block.
- Otherwise, use a 1ms RTOS tick delay instead of 2ms.
- Sample PCM bridge: 2048 stereo frames at 44100Hz (~46.4ms); one block is
  256 frames (~5.8ms). Do not infer zero underruns from a healthy FREE
  snapshot; the 16-bit UDR counter records past FIFO-empty interruptions.
- New counters:
  - `PCM RMAX`: longest HxCMOD 256-frame rendering interval (microseconds,
    **including** sample SPI cache reads).
  - `PCM SMAX`: longest 1024-byte SPI transfer to HDMI PCM FIFO (µs).
  - `PCM GMAX`: largest limiter/gain interval (µs).
  - `PCM DMIS`: maximum sample cache misses occurring during one PCM block.
  - `LOW`: minimum observed FIFO frames queued after first eight blocks.
  - `SMP SPI B`: cumulative bytes transferred from FPGA to per-voice caches;
    `PG`: PCM page size.
  - Existing `UDR MIS ERR` and `PF B E`, `PH EV` remain.

**Timing interpretation:** one 256-frame block consumes 5805µs of HDMI
audio. If `RMAX + SMAX + GMAX` regularly exceeds this, the CPU cannot
sustain real-time production at that moment without stored PCM headroom.
Single spikes may still be absorbed by the FIFO; correlate with UDR slope.

## Windows PowerShell: reusable one-command Stage2 scripts

The repository root contains [J2R8.ps1](../../../J2R8.ps1), which configures
the Bouffalo SDK, Make, CMake and RISC-V compiler paths automatically from the
checkout's parent folder. The script also generates and validates a SHA256
build manifest so an old binary cannot be mistaken for the current source.

Clone into an **isolated** directory; do not overwrite the working J2R6 tree:





```powershell
$j2r8="C:\AppleIIgsDev_02\a2fpga-jukebox-j2r8"; git clone --single-branch --branch petar/mod-j2r8-16kpattern-8ksample-20261121 https://github.com/ppuskari/a2fpga_core.git $j2r8; if($LASTEXITCODE -ne 0){throw "Clone failed"}
```

Every subsequent invocation is a single line from that checkout:


```powershell
Set-Location $j2r8
.\J2R8.ps1 Build
.\J2R8.ps1 Detect
.\J2R8.ps1 Flash
.\J2R8.ps1 CheckRuntime
```

Or build and flash with a single command (a typed confirmation is still
required):


```powershell
.\J2R8.ps1 BuildFlash
```

For a custom SDK or compiler location, use `-DevRoot`, `-SdkRoot`, or
`-ToolchainBin`. Run `.J2R8.ps1 Help` to see all supported arguments.

### Important: what flashing "verification" actually means

The underlying programmer offers **three independent operations**:

1. **Write** Stage2 at address `0x40000`. The wrapper checks the flash
   command's return and failure output, but does not claim a byte-verified
   flash image just because writing reported success.
2. **Post-reboot USB detection.** After a normal reboot, the Sipeed signed
   Stage1 runs first. The programmer may report `[PARTIAL]` while Stage1 has
   not chain-loaded Stage2 yet. This is a **timing/state observation, not an
   indication that the flash write failed**. To avoid false alarms, Flash
   passes `--skip-verify` and CheckRuntime is a separate command.
3. **Optional byte readback from the BootROM.** Use
   `.J2R8.ps1 VerifyReadback` with the board in UPDATE mode. The BL616
   BootROM readback path can have separate tool/output-location failures.
   A failed readback is **not** proof that Stage2 flash failed, and a
   successful USB boot is **not** byte-readback verification. The optional
   command fails explicitly if it cannot compare the bytes.

**No Stage1/FPGA flash writes occur in this script.** The existing J2R6
Stage2 binary remains the physical rollback choice. After programming, use
the J2R8 MOD OSD to confirm `MOD MCU CACHE=16384B` and
`MOD SMP CACHE=8x8192B` on a test MOD. An ordinary USB device
detection by itself does not establish which Stage2 firmware version ran.


## Repeatable hardware A/B acceptance sequence

1. Verify the old known-good four-channel MOD still plays with `UDR=0`.
2. Run `3EDGES.mod` and compare UDR growth and pattern `PF/B/E` to J2R6.
3. Run `A_clown_in_the_moon`; prior J2R6 reference UDR=43, MIS=6374.
4. Run `cheer.mod` through its dense drum solo. Report first audible dropout,
   UDR total and slope, `MIS`, `ERR`, `RMAX`, `SMAX`, `DMIS`, `LOW`,
   `PF/B/E`, `PH/EV`, and the sample `SPI B/PG` count.
5. Compare on approximately the same playback sections or elapsed frames.
   UDR and MIS are cumulative, not rates. A lower miss count by itself is
   not proof of better audible quality.
6. If any new regressions occur, restore the J2R6 MCU Stage2 baseline.
   Do not change working FPGA / A3 flash configuration.

Host GitHub Actions run HxCMOD PCM parity, SoundTracker 15-instrument,
48 x 8CH pattern transitions, 16KiB pattern LRU eviction, 1MiB SDRAM
staging, PCM FPGA bridge, ROMless mailbox and native IIgs DOC preservation.
Native Bouffalo SDK compilation and physical `cheer.mod` audio are separate
validation gates.
