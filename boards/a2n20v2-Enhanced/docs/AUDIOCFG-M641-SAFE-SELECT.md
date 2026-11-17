# M641-safe AudioCFG companion for existing A3 FPGA

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
