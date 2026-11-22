# J2R10: quiet audio console + dormant SSI/Mockingboard/DOC diagnostics

J2R10 is **based on the actual hardware-validated J2R9B** branch.
Preserve the J2R9B **MCU Stage2 binary and matching source revision**
as the rollback. The 2KiB × four sample windows per voice, 16KiB
pattern LRU, HxCMOD sound, HDMI 44.1k PCM, PCM512 bulk-only transfers,
bytewise FPGA SDRAM, +8dB gain and -2dB limiter **are unchanged**.

## Why

J2R9B plays 8-channel `3EDGES.mod` for 6+ minutes
and the demanding `CHEER.MOD` for 3+ minutes with
`UDR=0`, `E=0`, `ERR=0` and excellent sound.
The remaining avoidable activity is the debug/telemetry screen:

- `ssi263_hybrid_task` emitted **five P10 status lines every 10 seconds**,
  whether or not speech was playing, including CPU/SPI timing probes,
  underrun counters and PCM suspension counts.
- Visible `osd_log()` repainted the *entire* FPGA 23-row text console
  for every single logged line, clearing the 2KiB page and rewriting
  all rows through the shared bytewise FPGA SDRAM SPI link.
- MOD performance stats emitted two lines every 384 blocks (~2.23s),
  plus five extra lines every fourth interval, potentially creating
  seven consecutive full-screen repaints.

## MCU Stage2 changes (ready for physical test)

1. `SSI263_DIAG_COUNTERS=0` by default: compile out P10 idle
   telemetry, five-line 10-second reports, model/SPI timing probes,
   over-budget/slow counters, pause/resume stats and late-event counts.
   **No changes** to live SSI synthesis, event FIFO reads, event-loss
   fault detection, PCM suspension ACK, bus timing or PCM scheduling.
   Important speech error messages remain logged. To resume full P10
   instrumentation later, configure `SSI263_DIAG_COUNTERS=1` in CMake.
2. `osd_log()` **never** writes FPGA SDRAM. It only appends its
   line to the MCU SRAM 23-line history ring (and optionally Telnet).
   The existing menu/HID task calls `osd_console_service()` once
   per poll; the service paints the screen only if visible AND dirty
   AND at least 1 second has elapsed since the previous repaint.
   A user-requested `osd_console_show()` paints immediately, then
   clears the dirty flag. Hidden or locked-out console never draws.
   No new tasks, polling loops, or timer interrupts are introduced.
3. MOD performance diagnostic snapshots are preserved, but reduced
   to **one 7-line buffered batch approximately every 8.9 seconds**,
   instead of repetitive 2-line/5-line updates.
   This keeps UDR, MIS, ERR, RMAX, SMAX, DMIS, LOW, PF/B/E, PH/EV
   available for stress investigations. No per-sample changes.
4. A new compiled firmware identifier `MOD LOG=QUIET1HZ`
   distinguishes J2R10 from the proven J2R9B build. All original MOD
   cache and SPI configuration OSD lines remain unchanged.

## FPGA source trim (OPTIONAL, do not flash during MCU validation)

Only the two 16-bit **SSI263 transport statistics registers**
(underrun and overrun) are disabled in a **newly synthesized** board
image through the bridge parameter `ENABLE_PERF_COUNTERS=0`
in `top.sv`. Synthesis can optimize their unused
increments and constant-zero status bytes.

Critical **event FIFO overflow and sequence counters remain live**.
The SSI status byte addresses and SPI protocol remain unchanged.
The existing RTL testbench continues to exercise legacy counters
with the bridge parameter's default `ENABLE_PERF_COUNTERS=1`.
A new testbench checks that the disabled-counter variant preserves
speech PCM output and event sequencing while reporting zero stats.

- The DOC native debug outputs are already unconnected in `top.sv`,
  so normal FPGA synthesis prunes unused observation logic.
- `DebugOverlay.ENABLE` is already fixed to zero in top-level
  synthesis, so this is not an active FPGA overlay load.
- The Mockingboard/DOC envelope, sustain, de-clicker, and activity
  state must NOT be deleted: those are real audio functions, not
  gratuitous debug counters.
- W5100 debug/port-B diagnostics are separate from speech/MOD and are
  untouched because they also serve independent network validation.

**No FPGA change is needed for the J2R10 MCU quiet-console trial.**
Do not flash or rebuild the current FPGA golden bitstream merely to
save these two counters. If later evaluating gateware resources, build
and test the HDL changes in an isolated configuration and retain the
existing flash as a proven hardware rollback.

## Windows PowerShell: safe MCU-only J2R10 test

New isolated checkout (keep J2R9B and J2R9A untouched):

~~~powershell
$j2r10="C:\AppleIIgsDev_02\a2fpga-jukebox-j2r10"; git clone --single-branch --branch petar/mod-j2r10-quiet-console-20261122 https://github.com/ppuskari/a2fpga_core.git $j2r10; if($LASTEXITCODE -ne 0){throw "J2R10 clone failed"}
~~~

Single-command BL616 native build with automatic SDK/GCC/Make paths,
tracked-source fingerprint and binary SHA256 manifest:

~~~powershell
Set-Location $j2r10; .\J2R10.ps1 Build
~~~

Then put BL616 into UPDATE/BootROM mode. Write **only MCU Stage2 at
0x40000** after typed confirmation:

~~~powershell
.\J2R10.ps1 Flash
~~~

Reconnect without UPDATE. The optional runtime USB enumeration check
is separate from actual BootROM byte readback (which may fail due to
Bouffalo tooling and is not confused with Stage1's transient PARTIAL):

~~~powershell
.\J2R10.ps1 CheckRuntime
~~~

In the advanced console, after starting a MOD, expect:

    MOD SMP WIN=4x2048B
    MOD SPI=PCM512 SDRAM=BYTE
    MOD LOG=QUIET1HZ

No further periodic `P10 B=`, `P10 CPU=`,
`P10 RATE=`, `P10 R10 SK=` or
`P10 R11 PA=` should appear.

## Hardware acceptance matrix

1. Known-good four-channel MOD: startup, audio and menu unchanged;
   SDRAM pattern/sample sentinels pass; `UDR=0` and
   `E=ERR=0`.
2. `3EDGES.mod` (48 patterns × 8 channels):
   sustain ≥3 minutes with the ordinary Apple IIe screen displayed.
   Inspect the console briefly. Compare against J2R9B
   `RMAX≈24,876us`, `SMAX≈3,591us`, `UDR=0`.
3. `CHEER.MOD` (34 patterns × 8 channels):
   listen to the busy drum solos, compare J2R9B
   `RMAX≈20,008us`, `SMAX≈648us`, `UDR=0`.
4. Keep the console **visible for 1–2 minutes** for a second A/B:
   one FPGA refresh per second maximum, versus the previous
   complete redraw on *every* line.
5. Return to Apple IIe video and confirm menu control and music are
   unaffected. Speech, Enhanced Mockingboard and DOC modes are not
   retested by a MOD-only smoke test, so do not claim their full
   hardware regression has passed without a separate check.

### CI and physical limitations

GitHub CI compiles the actual MCU console C implementation against
mock SPI/OSD and verifies 1Hz batching, immediate show, hidden
lockout and Telnet tee. It syntax-compiles the real SSI speech
task with the diagnostics enabled and disabled, and simulates both
SSI transport counter modes. Existing HxCMOD and HDMI regressions
are unchanged. This cannot guarantee BL616 SDK compilation or real
audio timing. Those still require the native build and the
four/eight-channel hardware tests above.
