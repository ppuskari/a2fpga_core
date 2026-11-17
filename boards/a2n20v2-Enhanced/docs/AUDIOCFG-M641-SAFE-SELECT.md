# M641-safe cold-boot Flash AudioCFG selection for existing A3 FPGA

This branch is based directly on the **working M641 MCU**. It changes
only the persisted settings layout (reusing reserved byte zero), the
Audio Config menu, the existing early `main.c` boot sequence by a single
small audio-selection transaction, and the SPI register write's 3us CS#
hold proven useful in R2. The FPGA/HDL and M641 disk.c are unchanged.

The currently installed A3 FPGA already routes:
- mode 0 Enhanced DOC Mockingboard + hybrid SSI263 (working M641 default)
- mode 1 Original dual-YM2149 Mockingboard + hybrid SSI263 (observed working
  after earlier deliberate MCU restart)
- modes 2 Native DOC and 3 Shared remain experimental; do not promote
  to SenseiPlay playback until the separate native-slot driver is tested

MCU cold boot sequence:
1. M641 board init, FPGA SPI init, FPGA readiness and bridge 0x30.
2. M641 settings_init() restores the saved AudioCFG byte.
3. One bounded 0x6F=mode transaction (up to 8 attempts), read 0x6F
   == (A0|mode) and 0x6B READ == (D0|mode). No F0/RESET injection.
4. **Unmodified M641** 0x60–0x67 slot writes and 0x6B commit; after
   that, FPGA rejects further audio-mode writes until cold power-on.
5. **Unmodified M641** USB host initialization, disk thread, CardROM
   inhibition release and 0x2E Apple II reset release.

Audio failure logs FALLBACK and must not change normal M641 boot timing.
No extra waits, reset holds, late retries or reset-release paths.

Set Original in AUDIO CONFIG and select SAVE FOR NEXT BOOT (ENTER).
**Remove all Apple II / Tang Nano / Debug USB power and then power up
once.** An MCU-only restart will NOT unlock A3's mode register. Verify
FLASH SAVED, FPGA BOOT REQUEST and FPGA ACTIVE AUDIO all say ORIGINAL MB,
FPGA ROUTING A3 VERIFIED, normal physical Slot 6 Disk II autoboot, one
startup sequence, and actual AY PSG + SSI263 output. Repeat three cold
boots, then switch to Enhanced and back.

Preserve the known-working M641 MCU Stage 2 binary so restoring that
firmware alone always recovers the previously tested Enhanced route.
Do not overwrite BL616 Stage 1 at 0x0. If audio reverts to Enhanced,
capture the early AUDIOCFG diagnostic and menu readbacks; do not
replace normal Apple boot release with a late FPGA rearm.

Source test: `py -3 tools/test_audiocfg_m641_boot.py`.
The script verifies the exact M641 disk.c git blob and order. It is
not evidence of successful BL616 compilation or a physical hardware pass.


## Guarded early audio rearm experiment

The user confirmed Flash Saved ORIGINAL while actual FPGA request and mixer
readback remain A0/D0 (Enhanced), even though a prior explicit FPGA F0
rearm allowed AY mode. The A3 0x6B lock survives MCU-only restarts if
the FPGA remains powered, so this firmware tries normal 0x6F selection
first, then (only if it fails and both the physical Apple II /RESET and
the 0x2E software release remain asserted/not released) performs one
boot epoch F0 rearm before the original M641 0x6B slot strobe.
The unchanged M641 disk thread remains the sole reset release owner.

If Apple reset is already released, it skips rearm. It reports
`AUDIOCFG PRE RST=<status> REL=<release> ARM=<0 or 1>` to distinguish
the guarded retry from a late-start fallback. A failure logs FALLBACK
and must not block normal physical Disk II boot. This test has not yet
been compiled or hardware validated; preserve known-good M641 image.


## Explicit MCU + Apple reboot (manual menu action)

A normal MCU firmware restart merely jumps into BL616 XIP and does not
reload the Tang Nano FPGA. The A3 FPGA 0x6B slot strobe locks audio mode,
so MCU restart alone left Enhanced active even with Original saved. The
**Main Menu -> RESTART MCU** action now explicitly sends 0x6F=F0 on an
A3 FPGA before requesting the existing BL616 application restart. It
checks the FPGA reset-release latch 0x2E, up to three quick retries.
This is an *intentional* Apple II reboot: the FPGA clears the mode lock,
holds /RESET, and restarts its safety backstop. The MCU then performs
the regular M641 bridge/audio/slot/USB startup, and the **unchanged**
M641 disk thread performs the sole normal reset release.

A raw BL616 RESET button still does not automatically rearm the FPGA;
this is deliberate to prevent second-reset regressions at cold startup.
Use the Menu restart or remove all Apple/Tang/USB power. Automatic
power-on mode selection is unchanged and may still report FALLBACK;
that must be diagnosed separately. No changes to FPGA, disk.c or FPGA
reset timers.


## Cold-boot SDRAM-ready gate removed

The prior firmware skipped all A3 mode writes if its initial
`fpga_spi_wait_ready(2000)` returned false. That function requires BOTH
FPGA_CONFIGURED and SDRAM_READY. The audio `0x6F` and route `0x6B`
registers do not depend on SDRAM initialization. Thus a cold startup
could incorrectly skip saved Original mode and then lock Enhanced with
M641's normal `0x6B` slot commit. Later MCU restarts can succeed after
SDRAM initialization, misleadingly suggesting flash settings were lost.

The new firmware probes the A3 register signatures directly and applies
the persisted 0..3 audio selection with readback in a bounded 16-attempt
loop (50 us spacing; no prolonged reset hold). It does not send F0,
reassert Apple reset, or defer the physical Slot 6 disk boot. Failure
keeps the previous Enhanced fallback and logs `AUD ... FALLBACK`.
The second boot log `AUD INIT RDY=<0|1> A3=<0|1>` distinguishes initial
SDRAM readiness from an accessible A3 audio-control register.

The menu's RESTART MCU action returns to the original M641 behavior:
it restarts BL616 application only. It intentionally does not reset
the Apple II. The earlier F0 reset caused a *warm* IIe restart which
can land at BASIC instead of the power-on disk autoboot vector;
PR#6 booting the Slot 6 drive manually confirmed the controller works.
**Only a genuine complete removal of all Apple/Tang/Debug USB power
can initiate a clean power-on autoboot and unlock the audio mode.**

Physical hardware test remains necessary. M641 disk.c, FPGA RTL,
slot configuration and reset-release timing are unchanged.
