# P10 — BL616/FPGA hybrid SSI-263 feasibility and transport specification

**Historical feasibility design (superseded by the implemented P10-R1 hybrid).**
The FPGA PCM/event queues, connected BL616/Pico C renderer, and
independent CI tests now exist on this branch. See
[P10-HYBRID-HARDWARE-TEST.md](P10-HYBRID-HARDWARE-TEST.md) for the
current source, build, Stage2 flash safety and hardware test instructions.
P9M remains a separate untouched rollback baseline.

## Why move complete acoustic synthesis to BL616

P9M measured 22,697 mapped logic units versus 20,736
available, an excess of **1,961**. This remains after removing
unused F18A and IIgs SHR video from the Apple IIe experiment.
The final Enhanced image must restore full IIgs/SHR support;
further video trimming is not the long-term solution.

P9M's SSI-263 full DSP includes:
- glottal generator, 15-bit LFSR, noise shaper,
- five switched-capacitor model filter stages, all F1/F2/F3/NAS
  coefficients, closures and per-field interpolation,
- an oversampled 193-tap output FIR and PCM conversion.

The BL616 host firmware has a 320 MHz RISC-V CPU (with FPU/DSP
capability) and already owns a **20 MHz SPI Mode 1** master link.
We can build/preserve the actual MIT Pico C model on the MCU and
keep the physical Mockingboard register/A/R path in the FPGA.

**Do not offload only the 193-tap FIR as a first solution**:
the serial FIR already uses one time-shared multiplier.
Moving the *entire* expensive SSI analog core is more likely to
recover the required logic without degrading its phoneme quality.

## Required boundary

```text
Apple IIe / IIgs CPU writes SSI registers $Cn40-$Cn7F
             |
             v
    FPGA: SSI R0..R4 + XCK + CTL + VIA right CA1/A/R
             |
      sequence-numbered, XCK-timestamped SSI WRITE FIFO
             |   SPI reads (new XFER space, proposed space 5)
             v
    BL616: pinned Pico SSI C model, entire audio synthesizer
             |
        44,100 mono, signed PCM16, BLOCKS with sequence
             |   SPI writes (new XFER space, proposed space 4)
             v
    FPGA: speech PCM FIFO -> sample-clock consumer -> gain/mute
             |
             +----existing Ensoniq DOC piano / AY FX HDMI mixer----> HDMI
```

**Never derive VIA A/R directly from the MCU's FreeRTOS scheduling.**
Apple-visible timing and status stay clocked in FPGA XCK, as
the working P6 SSI controller already demonstrated.
Any A/R early-lookahead semantics must be verified in FPGA before
deleting the legacy register controller.

This also provides functional independence: if the MCU is missing
or its speech service stops, only speech is silent; DOC piano,
HDMI, Apple slot access and Mockingboard A/R still work.
Use explicit underrun counters, no stale sample repeats.

## SPI bandwidth, buffering and latency

The actual shared driver `boards/a2n20v2-Enhanced/src/a2n20_bl616/
firmware/fpga_spi.c` sets SPI0 to 20 MHz, but calls
`bflb_spi_poll_exchange()` for **every byte**, and uses a FreeRTOS
mutex across transfers. Therefore **20 MHz clock != guaranteed
throughput or worst-case latency**.

- 44,100 x 2 = **88,200 payload bytes per second**, 705.6 kbit/s.
- A 512-byte PCM block is 256 samples = **5.805 ms**.
- The current seven-byte XFER header is only ~1.4% of a 512B write
  on the wire, but the per-byte software calls may dominate.
- 20 MHz wire-only payload capacity is 2,500,000 B/s, roughly
  28x the required average, ignoring protocol/software overhead.
- Proposed FIFO: 2,048 samples (4,096 bytes) = **46.4 ms**.
  Initial playback watermark 1,024 samples (23.2 ms).
- Aim for measured sustained throughput >= 500 kB/s and max
  scheduler lock stall < 10 ms during USB/disk/OSD stress.
  These are *proposed engineering gates*, not measurements.
- For each block return committed-sample count, free space,
  underrun/overrun counters and last-accepted sequence.
  A block must not partially overwrite unread samples.

A major integration detail: the HDMI sample clock originates from
`audio_timing` in the **27 MHz pixel clock domain**, not the
54 MHz speech domain. Use a real sample-clock CDC handshake into the
FPGA PCM FIFO consumer and verify 44.1 kHz *long-term rate match*.
Do not use two independent fractional clock generators that slowly
drift or duplicate/drop audio without a control mechanism.

## Proposed not-yet-implemented SPI extension

The existing protocol has XFER space 0 (256B local), 1 (SDRAM),
2 (bus event FIFO) and 3 (W5100). The 3-bit field supports 0..7,
so spaces **4 and 5 are provisional available design candidates**.
Review other branches/firmware dependencies before assigning.
Do NOT implement the audio transport by commandeering space 0
or the existing space 2 used for bus diagnostics.

- Space 4: MCU -> FPGA PCM16 block sink. Endian little;
  payload into 2,048-sample ring, with explicit packet framing,
  sequence and optional CRC; no silent lost writes.
- Space 5: FPGA -> MCU dedicated SSI register-write-event FIFO.
  Each event contains register 0..4, value, XCK timestamp and
  monotonically increasing sequence. Overflow must be reported and
  force a retrigger/resync, not silently drop phonemes.
- A small reserved group of SPI registers (assign after inspecting
  all 0x00..0x7E handlers) supplies occupancy, power, underruns,
  FIFO reset, protocol version, and generation/epoch counters.
- Event timestamp and PCM block generation must share a meaningful
  audio epoch. The MCU synthesizer must account for the deliberate
  buffer latency when applying timestamped phoneme changes.

Do not treat new register protocol as working until both directions
pass a real-hardware full-speed stress and CRC test.

## Stage A: benchmark CURRENT FPGA link before implementing audio

Opt-in firmware-only files:
- `firmware_host/ssi263_spi_bench.[ch]` (source resides under the
  full board firmware_host path)
- `firmware_host/main.c` calls the benchmark only with
  `SSI263_HYBRID_SPI_BENCH` compile definition.
- `firmware_host/CMakeLists.txt` compiles the dormant benchmark.

Benchmark copies/retrieves 256B bursts using existing space-0
local RAM 64 times per direction, measures elapsed microseconds,
verifies all bytes and emits W/R throughput and errors to
console/OSD. Runs once after FPGA ready and menu init but before
FreeRTOS scheduler starts. **It is disabled by default.** The 256B
space-0 RAM is temporarily overwritten, so do not enable this
in release firmware or concurrently with a user of local space 0.

To enable explicitly, add `-DSSI263_HYBRID_SPI_BENCH` via
the firmware_host CMake build settings and rebuild the BL616
firmware. Do not flash untested firmware solely to investigate an
FPGA RP0006 limit; first establish a rollback image and correct
flash offset (stage2) for the user's BL616 board.

This measures unloaded sustained transfer with the existing
polling driver, NOT worst-case latency or multitask load.
The latter needs a second stress test after prototype FIFO/priority
scheduling and instrumented disk/USB activity.

## Stage B: enable a *new* hybrid compile-time profile

Compile out old P9 HDL DSP and its ROMs entirely (no dangling audio
ROM). The production FPGA keeps register controller, A/R, timing
and PCM buffer only, plus unchanged DOC+AY/HDMI mixer.
The MCU runs pinned SSI C in a deterministic high-priority audio
task with bounded FIFO/SPI work; other tasks never block an audio
block indefinitely. Prefer SPI DMA / whole-burst transfers only
after proving compatible with existing SPI slave CDC and other users.

## Stage C: validate before claiming full IIgs support

1. FPGA/BL616 event FIFO + PCM FIFO randomized RTL tests, with
   underflow, overflow, reset, reordering and warm-restart.
2. MCU transfer benchmark; measure time *per 512B block* under
   simultaneous disk, USB and network loads; monitor sample drops.
3. Compile actual pinned Pico C engine for BL616; profile CPU %
   per audio frame, DSP numerical output, FPU speed and heap/stack.
4. Start with the exact Demo Disk 1 SSI register trace, compare
   generated PCM byte/spectrum against host C reference.
5. Prove native IIe + IIgs slot/VIA and real recording, then
   reenable full VGC/SHR, remove duplicate synthesizers from
   the FPGA, and verify Gowin synthesis/place/route/timing.

**Full MCU sound synthesis may still require performance tuning.**
The nominal 320 MHz clock gives only ~7,256 CPU clocks per
44.1 kHz output sample, shared with all other firmware tasks;
a full 4x/193-tap software FIR is computationally nontrivial.

## Current baseline remains P9M

P9M Gowin RP0006 = 22,697 / 20,736, over by 1,961.
P10 is a *measured feasibility investigation*, not another
unsuccessful speech-enabled bitstream.
