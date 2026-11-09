# P10-R1: Real BL616 + FPGA hybrid SSI-263 hardware test

**Branch:** `petar/ssi263-p10-hybrid-feasibility-20261109`

**Status:** both source halves implemented; portable CI tests passing.
**Gowin fitting and BL616 SDK build are NOT yet hardware-verified.**
This is a test candidate, **not** the new golden baseline.

## Why the hybrid is necessary

P9M synthesis: 22,697 mapped logic units; device limit 20,736
(1,961 units over). P9M already removed unused IIgs graphics, and that
temporary trim is incompatible with our final IIgs target.

P10 restores `IIE_SPEECH_VIDEO_TRIM=0` (full IIgs VGC/SHR support),
then compile-time removes all P8/P9 formant/glottal/noise/193-tap FIR
hardware from the selected SSI slot path. It retains:

- SSI-263 CPU writes, R0–R4, CTL, XCK and A/R in the FPGA
- right VIA CA1, both AY PSGs, Apple IIe/IIgs slot interface
- the entire P6 DOC multisample piano, envelopes, native AY/FX
- existing BL616 SPI system, SDRAM, HDMI video **including IIgs SHR**
- existing HDMI audio mixer with `MB_SPEECH_GAIN_NUM=1`

The BL616 host firmware instead compiles the **pinned Pico research
SSI263 C model**, including its five formants, die-derived phoneme
parameters, noise shaping, release rules and native 193-tap FIR.

The C model is still a research reconstruction, not proven exact silicon.
A/R uses the independent hardware-timed P6 SSI controller; its
approximate timer semantics differ from the C model's full early
lookahead. Hardware speech may be delayed by buffered transport.

## Data flow

```text
Apple IIe/IIgs Mockingboard SSI bus
  FPGA SSI controller -> 256 x 64-bit ordered write-event FIFO
  via BL616 SPI Mode1, XFER space 5, 8-byte event packets
  BL616 FreeRTOS task: ssi263_write() -> ssi263_run(128)
  native C floating point formant/FIR and ssi_pcm16()
  via BL616 SPI Mode1, XFER space 4, 256B PCM16 blocks
  FPGA 2048 x 16-bit PCM FIFO, start watermark 512 samples
  PCM sample strobe from ACTUAL 44.1 kHz HDMI clock
  FPGA DOC + AY audio mixer -> HDMI output
```

- Audio payload target: **88,200 bytes/s** mono PCM16 at 44.1 kHz.
- Host audio task processes 128 samples per block (~2.90ms).
- Start watermark 512 samples (~11.6ms).
- Firmware targets ~1024 buffered samples (~23.2ms).
- SPI shared transport already set to 20 MHz (theoretical 2.5MB/s),
  but each byte is polled and USB/disk/network clients share a mutex.
  **Sustained/99.9th latency and CPU headroom are not hardware measured.**
- Hardware PCM underflow -> silence + count; MCU missing -> silence;
  CTL powerdown -> immediate gate + buffer reset. No stale PCM replay.
- FPGA A/R is **not** dependent on MCU thread scheduling.
- Event count, timestamp (XCK ticks), sequence, overflow/error
  counters and FIFO occupancy are available to the MCU.
- First listening build applies events promptly, but does not yet
  reproduce their timestamp-accurate placement in the FIFO timeline.
  That work is necessary before calling this an exact SSI-263 emulator.

## File changes

FPGA:
- `hdl/mockingboard/ssi263_slot.sv` — P10 compile-time hybrid path
  retaining `ssi263_control`, no large DSP synthesis
- `hdl/mockingboard/mockingboard.sv` — new SSI event + PCM ports
- `boards/a2n20v2-Enhanced/hdl/ssi263_hybrid_bridge.sv` — event FIFO,
  2048 PCM samples, HDMI sample tick CDC, SPI protocol/status,
  safe power-down and underrun handling
- `boards/a2n20v2-Enhanced/hdl/bl616/bl616_spi_connector.sv` —
  XFER spaces 4 and 5; existing spaces 0-3 unchanged
- `boards/a2n20v2-Enhanced/hdl/top.sv` — audio wiring, full IIgs video
- Gowin project includes the new bridge HDL

MCU:
- `boards/a2n20v2-Enhanced/src/a2n20_bl616/firmware_host/ssi263_hybrid.c`
  reads 8B phoneme events, renders 128 samples, streams PCM, logs
  blocks/CPU overruns/sequence gaps/occupancy.
- `.../firmware_host/CMakeLists.txt` includes both pinned
  `reference/ssi263/pico-v1.0.1/ssi263.c` and `ssi263dsp.c`
  and math library; normal `main.c` launches speech task.
- Earlier opt-in SPI bandwidth benchmark remains present and
  disabled unless `SSI263_HYBRID_SPI_BENCH` is explicitly compiled in.

## FPGA build (PowerShell 5.1, paste each line separately)

```powershell
git clone --branch petar/ssi263-p10-hybrid-feasibility-20261109 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p10
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10
```

```powershell
py -3 tools\extract_synthlab_piano.py --download
```

```powershell
py -3 tools\generate_ssi263_voice.py
```

```powershell
Start-Process .\boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj
```

Gowin synthesis first. Target **<=20,736 logic**, preferable
<=19,500 for routing/timing headroom. Run P&R and timing only if
synthesis fits. Note LUT/ALU/ROM/SSRAM/BSRAM counts, WNS and any
inferred-latch/ROM warnings. The P8/P9 DSP modules may still be in
the *parser list* because the project retains source files; selected
P10 `generate` path must not elaborate them.

## BL616 firmware build (same repository checkout)

In the existing Bouffalo SDK v2.3.27 + RISC-V toolchain environment:

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
```

```powershell
make -j4
```

```powershell
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin
```

Build prerequisites are unchanged from your working BL616 host SDK.
The committed C syntax and stub integration compile in CI but do NOT
prove Bouffalo SDK cross-compilation or MCU real-time performance.

### BL616 Stage 2 FLASH — read before any flash

**Never use `make flash`, the SDK flasher, or address 0x0.**
The signed factory **Stage 1 must be preserved**. Only deploy the
compiled unsigned P10 host binary as Stage 2 to **0x40000**, using
the repository's guarded Python programmer. Keep a copy of your
working previous `a2n20_bl616_host_bl616.bin` first.

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10\boards\a2n20v2-Enhanced\src\a2n20_bl616
```

```powershell
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin
```

The tool can prompt for boot mode and uses the Stage2-safe flow.
Ensure the intended board is selected and use its verification option
as appropriate. Do not program unless Gowin fitting, P&R and timing
also pass, and the previous firmware image can be restored.

## Hardware test sequence

1. Boot IIe or IIgs with FPGA bitstream and matching P10 BL616
   Stage 2 firmware. Check normal menu/USB and DOC piano first.
2. Listen to virtual piano (should retain P6 quality), then MB demo
   disk music/FX/explosions before testing speech.
3. Look for `P10 SSI263: Pico C hybrid online` on OSD/console.
4. Execute Demo Disk 1 speech (`S/ONLY`, `A MESSAGE`); record
   unprocessed 44.1 kHz WAV and note volume/intelligibility.
5. Inspect `P10 speech blocks=... slow=... seqgap=... fifo=...`.
   No increase in `seqgap`, low `slow`, and stable FIFO above
   watermark are the initial acceptance cues. Investigate persistent
   silence, static or underflows before changing piano gain.
6. Check IIgs normal modes, 80-column and Super Hi-Res if compiled.
7. If needed, revert FPGA to P6/P9M and BL616 Stage 2 to previous
   working binary. Do NOT assume P10 can run with unrelated MCU
   firmware — the hybrid will intentionally produce no speech.

## Validation so far

- GitHub Actions:
  `.github/workflows/ssi263-p10-hybrid-build.yml`
- RTL: SPI memory space4/5, ordered events, PCM ring, watermark,
  HDMI sample tick, underrun, reset, powerdown, A/R in native slot.
- MCU C: syntax checked with mocked FreeRTOS/Bouffalo SPI headers.
- Pinned Pico C model: host compiled and rendered a nonzero waveform.
- Existing native Pico source used; no new phoneme approximation.
- **No Gowin mapping, timing, FPGA/BL616 hardware test or MCU SDK
  cross-build claim yet.**

This branch is intentionally separate from stable P6 and the P9M
experiment. Legacy SSI HDL sources remain in Git until P10 passes on
hardware, at which time we can consolidate them.
