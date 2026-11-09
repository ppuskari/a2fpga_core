# P10-R4 — Rebase BL616 hybrid speech on actual Enhanced MCU baseline

**Target board: `boards/a2n20v2-Enhanced` only.**
**Branch: `petar/ssi263-p10r4-enhanced-mcu-sync-20261109`.**

## What the hardware proved

The real IIe/Enhanced hardware photo shows P10 Pico C is running and
regularly producing 128-sample blocks, but the default `SLOW` counter
is nearly equal to the total block count:

- `BLOCKS=181048`, `SLOW=181020` (99.9845% >2.5 ms).
- Consecutive 3-second status entries grow by roughly **664** blocks:
  664 x 128 / 3 = **28,330 samples/s**, only 64.2% of the necessary
  44,100 samples/s. This is a rough estimate from display timestamps.
- Speech is **not** 16x too slow; it needs approximately a **1.56x
  throughput improvement**. `SLOW` refers to rendering plus
  PCM transfer exceeding the 2.5 ms threshold, **not necessarily
  dropped SPI packets**.
- The log does not fully display `SEQGAP` because the 39-column
  OSD truncates the old line.
- The user also recorded the optical S/PDIF audio, but the WAV was
  not attached to this discussion; no acoustic comparison was made.

## Critical source-lineage correction

The previous P10 was built from a **stale Enhanced MCU source line**
and omitted an existing keyboard/media-remote class driver,
early slot-map programming and boot-timeline instruments.

The official upstream `a2fpga/a2fpga_core` fork parent is old
(August 2026). The user's **`ppuskari/a2fpga_core`** already has
later Enhanced-specific work:

- `main` includes original **`usbh_hidinput.c/h`**, which handles
  boot keyboards, consumer-control/media remotes and multi-interface
  devices. It uses `usbh_hidinput_buttons()` in the 20ms
  XInput/menu polling task.
- `petar/mcu-timeout-hid-upstream-20261106` includes tested
  **15-second MCU menu and console idle handoff** (Nov 6).
- `main.c` also includes `boot_timeline.c/h`,
  `g_slots_applied_early`, readback-verified slot assignments,
  early A2 bus-ready and 0x6B slot-reconfiguration strobe.
- Existing newer `disk.c/h`, `telnetd.c`, `fwupdate.[ch]`,
  `usb_config.h` are synchronized with this `main` baseline.
- R3's hand-built `usb_kbd_menu.[ch]` is deleted, not linked.
  It was insufficient: did not handle consumer-page HID remotes.

P10-R4 takes the original Enhanced input/boot/reset components,
then layers **only** the P10 Pico speech task and native model
build, the useful USB MSC block geometry diagnostics, and a
nonblocking failed-mount video hide at 15 seconds. A successful
mount still hides the console after 1.5 s.

**The FPGA RTL is unchanged from the timing-closed P10-R2 build**:
do not rebuild or reprogram Gowin for this MCU-only iteration.

## MCU scheduling / audio optimization

P10 originally started the expensive speech task at FreeRTOS
priority `CONFIG_USBHOST_PSC_PRIO+2` = **30**. USB gamepad/menu,
disk and W5100 service ran at **29**; USB PSC at **28**.
Audio running over budget could starve menu and disk work.
P10-R4 runs speech at priority **28**, below those tasks.
That is a system responsiveness fix, not a promise of better
speech throughput.

The pinned Pico model uses `typedef float real;` but many bare
floating constants would promote operations to double, which
is expensive on the BL616's single-precision FPU.
The MCU **only** now compiles `ssi263.c` and `ssi263dsp.c`
with `-O3 -fsingle-precision-constant`.

GitHub CI generated 12,288 samples in standard reference and
optimized builds: **Pearson/cosine correlation 0.999998,
SNR 55.16 dB relative to the native reference**. This is a
narrow numerical fixture, **not** proof of exact real SSI silicon
fidelity. Actual BL616 speedup and audio quality remain to be
measured. The model source and generated ROM are unchanged.

Old logging every 3 s flooded the video page and shortened
visible values. R4 logs three short lines every 10 s:

```
P10 B=<blocks> S=<slow> G=<seqgap>
P10 RATE=<samples/sec>/S OVR=<true_overruns> FIFO=<occupancy>
P10 CPU=<peak_model_us>US SPI=<peak_spi_us>US UND=<underruns>
```

For each 128-sample/44.1k block, the real-time budget is **2902 us**.
`S` is the older >2500 us guard; `OVR` counts true >2902 us
(render + SPI) in the reporting window. `CPU` and `SPI` are
separate observed peak durations. The `UND` counter comes from the
FPGA PCM buffer and indicates actual late/empty data at playback.
Expected full-speed sample rate: **44100/s**.

## One-line Windows PowerShell 5.1 build instructions

From any directory, use **one command per pasted line**:

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10
```

```powershell
git status --short
```

Check the output before switching if local source files were modified.

```powershell
git fetch origin
```

```powershell
git switch --track origin/petar/ssi263-p10r4-enhanced-mcu-sync-20261109
```

```powershell
Set-Location .\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
```

```powershell
make -j4
```

```powershell
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin
```

The MCU's actual SDK 2.3.27 cross-build has **not yet been run** for
P10-R4; GitHub CI used host C and model-output tests plus lineage
checks. Do not flash until SDK build links and a rollback copy of the
previous Stage2 is made.

**If verified working and ready for the MCU-only hardware test**,
leave the P10-R2 FPGA loaded and use the existing guarded programmer
on the `a2n20_bl616` parent folder:

```powershell
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

**Never use `make flash`, do not touch Stage1 at 0x0.**
The previous `--verify-flash` readback tool returned a missing
`flash.bin` warning and did not conclusively compare bytes.

## Acceptance checks

1. USB HID keyboard TAB toggles Apple↔MCU as the original Enhanced
   driver intended. Enter/Esc/arrows operate the menu; media remotes
   retain their consumer-page Home/Back/Volume mapping. No duplicate
   HID handler is linked.
2. The MCU console returns to Apple video after 15 seconds even
   on USB disk failure; pressing TAB restores the menu.
3. Early slot map/reset handshake works, as in current Enhanced code.
4. `P10 RATE` approaches 44,100/s while speech is powered.
   `OVR` remains low; `UND` and `G` do not increase.
5. If `CPU` dominates, inspect `ssi263.c` chip-run loop and FPU.
   If `SPI` dominates, fix per-byte polling and shared mutex
   contention. Never degrade the DOC piano/AY effects to mask issues.
6. Check real IIe and IIgs operations with full IIgs video bitstream,
   then compare the user's optical capture against native SSI reference.
