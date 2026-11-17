# AUDIOCFG A3 — Runtime boot audio routing and experimental native DOC

Branch: `petar/audiocfg-a3-runtime-audio-20261116`
Base: validated A1/A2 four-mode menu, originally forked from M641 golden.
The M641 and MB6.6 development branches are untouched.

## Scope and ownership

The FPGA has **one** DOC5503 renderer and one waveform memory bank pair.
A3 changes audio ownership only at cold startup. The BL616 writes SPI
register `0x6F` before the slot-map `0x6B` strobe. Afterwards the FPGA
rejects mode changes until its own device reset; saving menu changes
alone never reconfigures a playing DOC.

| Saved code | Menu | Mockingboard bus | DOC host owner | Audible source |
|---|---|---|---|---|
| 0 | Enhanced MB | yes | M641 AY-to-DOC translator | DOC piano/FX + hybrid SSI263 |
| 1 | Original MB | yes | none | two YM2149 PSGs + hybrid SSI263 |
| 2 | Native DOC | no | native Apple CPU | DOC, no MB/SSI263 |
| 3 | Shared | yes | native Apple CPU | two YM2149 PSGs + native DOC + hybrid SSI263 |

The Shared mode uses the original YM2149 path and **not** the
AY-to-DOC translator, so the native player exclusively owns DOC
oscillators and waveform RAM. It does not implement a simultaneous
DOC-enhanced Mockingboard and Native DOC.

Native/Shared HDMI uses the baseline native +3dB calibration; Enhanced
retains the exact M641 8x/-2dB limiter and speech pre-compensation.
Do not switch modes without a complete cold reboot.

## Native IIe slot transport — first hardware implementation

The current virtual Mockingboard slot is typically Slot 4.
Address translation tracks the configured virtual slot (`C0n0` through
`C0nF`, where `n` is the selected slot). For Slot 4:

| IIe address | Read | Write |
|---|---|---|
| `$C0C0` | Sound GLU control register | Sound GLU control / volume |
| `$C0C1` | DOC register mirror / last Sound RAM data | DOC register or waveform byte |
| `$C0C2` | Address pointer low | Address pointer low |
| `$C0C3` | Address pointer high | Address pointer high |
| `$C0C4`–`$C0C6` | ASCII `D`, `O`, `C` | ignored |
| `$C0C7` | protocol byte `$11` (initial register-mirror interface) | ignored |
| `$C0C8` | `$A2` native / `$A3` shared | ignored |
| `$C0C9` | 128K extension state (`$10/$11/$13`) | ignored |

The register window `$C0C0`–`$C0C3` has IIgs Sound GLU write semantics
for `$C03C`–`$C03F`: `$C0C0` bit 6 selects Sound RAM vs DOC register
access, bit 5 auto-increments the pointer, low nibble controls volume.
The 128K unlock protocol remains `A2FP`/lock at DOC addresses E2-E6,
with extension bank rules unchanged.

On a *real IIgs host*, selecting Native/Shared also enables ordinary
`$C03C`–`$C03F` CPU writes. The IIe-only slot path remains separate
from the regular Mockingboard VIA range `$Cn00`–`$CnFF`.

**Compatibility limitations requiring A4 hardening:**

- DOC oscillator register reads are a writeback mirror (initialized at
  power-up and scrubbed after Apple reset); asynchronous internal DOC
  changes to oscillator registers are not yet reflected.
  E1 oscillator enable reads return the DOC's live enable state.
- Sound RAM reads currently return the last staged data byte, *not*
  the addressed SDRAM contents. Real RAM readback plus a bounded
  transaction/ready protocol must be implemented before data integrity
  or full IIgs native-driver parity can be claimed.
- DOC register reads are also issued to the DOC core to preserve its
  own read handling, but the CPU receives the mirror because DOC
  internal response latency is not bounded to the 1MHz bus cycle.
- Native DOC and Shared audible playback **require the Apple program to
  upload waveforms and initialize oscillators**; there is no default
  sample-bank preload in those modes.
- This is not yet a fully verified 65C02 application ABI or tool set.
  In particular, the planned SenseiPlay/NTP port remains a later step.

## First physical test sequence

0. KEEP the known-good M641 FPGA+MCU images on a recovery stick.
1. Run the usual generated ROM prep (SynthLAB piano and SSI263 voice).
   Build the FPGA from this A3 branch with Gowin. Check resource
   utilization and **timing violations** before flashing. Build and
   install the matching `firmware_host` BL616 MCU; only Stage 2 at
   `0x40000` should ever be flashed by a PC tool.
2. Start in saved mode 0 (Enhanced), cold power cycle. Expect console
   `AUDIOCFG A3: REQ=0 ACK (BOOT ROUTING)`. Play the exact M641 title
   and SSI263 speech tests, including TAB responsiveness.
3. Select mode 1 (Original), save via DOWN+ENTER, and cold power cycle.
   Expect `REQ=1 ACK`. Play the MB disk. YM2149 chip tones/noise,
   envelope, VIA IRQ and SSI263 should sound. Piano is *not* expected.
4. Select mode 2 (Native), save and cold power cycle. In Applesoft BASIC
   on the IIe with the card in Slot 4, the read-only probe is:

       PRINT PEEK(49348);PEEK(49349);PEEK(49350);PEEK(49351);PEEK(49352)

   Expected decimal results: `68 79 67 17 162`.
   The Mockingboard VIA should no longer drive the bus or IRQ.
   No native audio is expected before the client loads waveforms.
5. Select mode 3 (Shared), save and cold power cycle. The same probe
   should return `68 79 67 17 163`; MB music and SSI263 must
   remain available while native DOC registers are separately
   accessible from the device-space port.
6. Save Enhanced mode (0), reboot, and repeat M641 regression test.
7. With each mode, inspect HDMI initialization, storage boot, Hub/USB
   keyboard TAB input, video, and DOC diagnostics.
8. If any failure occurs, report selected mode, FPGA/MCU build stamps,
   console `AUDIOCFG` line, and which phase failed. Reflash known-good
   FPGA/MCU images without touching Stage 1.

## Build status

Source implementation committed and visually reviewed. No Gowin,
T-Head/BL616 build, timing closure or physical hardware tests have
been executed by ChatGPT in this branch. Do not promote or merge into
MB6.6 until these are complete. 


## A3 live-route verification — revision after hardware report

Earlier A1/A2 FPGA revisions acknowledge SPI mode 1 as `0xA1` on
register `0x6F` but have **no actual audio switching**. The A3 MCU
formerly printed `AUDIOCFG A3: REQ=1 ACK` for those old cores, creating
false confidence that Original mode was working. This is now corrected.

A3 FPGA implements a **new read-only register at SPI `0x6B`**:

| Register | A1/A2-only core | A3 core |
| --- | --- | --- |
| `0x6F` | `0xA0 | saved_mode` | `0xA0 | saved_mode` |
| `0x6B` READ | `0x00` | `0xD0 | effective_audio_route` |

`0x6B` WRITE continues to strobe slot reconfiguration and lock the
boot mode, unchanged. The A3 response is driven by the FPGA top-level
mixer-select predicates, rather than merely echoing flash settings.

On boot with Original (1), the expected A3 MCU line is now:

    AUDIOCFG A3: REQ=1 ROUTE=1 OK

The AUDIO CONFIG screen separately reports:

    FLASH SAVED       ORIGINAL MB
    FPGA BOOT REQUEST ORIGINAL MB
    FPGA ACTIVE AUDIO ORIGINAL MB
    FPGA ROUTING      A3 VERIFIED

If it instead shows `NO A3 CORE`, the installed FPGA is still A1/A2
(or an older build) even if the MCU was updated and `0x6F` returns
`0xA1`. In that case install the newly generated **A3 FPGA image**:

    boards/a2n20v2-Enhanced/impl/pnr/a2n20v2_enhanced.bin

Use the MCU's FPGA UPDATE menu (raw .bin) and verify the FPGA build stamp
changes. MCU firmware and FPGA are separate updates, so **flashing just the
MCU does not install A3 audio routing**. The A3 FPGA may retain the old
menu text if the MCU was not rebuilt; the new diagnostic requires both.

If the menu reports `A3 VERIFIED` with Original but music still sounds
like Enhanced, capture the FPGA/MCU stamps and audio behavior: that is a
real audio-routing defect requiring investigation, not an outdated core.


## A3-R1 boot latch fix (Nov 16, 2026)

Hardware observation: \`FLASH SAVED=ORIGINAL MB\` while both
\`FPGA BOOT REQUEST\` and \`FPGA ACTIVE AUDIO\` remain \`ENHANCED MB\`.
The previous \`A3 VERIFIED\` message meant only that the *two FPGA registers
agreed with each other*, not with saved settings.

Cause in RTL: an unconditional write to SPI register 0x6B during slot map
configuration locks audio_mode_r until **FPGA device reset**. The menu's
\`RESTART MCU\` only restarts the BL616 firmware; it does **not** reset the
FPGA, so the saved mode cannot be applied after a warm MCU restart.

**Boot rearm protocol:** at the start of every BL616 boot, before selecting
audio or issuing the slot-map strobe, the MCU writes 0xF0 to register 0x6F.
The updated FPGA then clears the old mode lock, asserts the Apple II reset
hold through the existing bus interface, clears the reset-release latch, and
restarts the 15-second failsafe. The MCU follows with saved mode 0-3,
verifies both register readbacks (0x6F = A0|mode; 0x6B = D0|mode), and
eventually writes 0x6B to reconfigure slots/lock the new personality.
The normal USB/media boot process then releases Apple reset via 0x2E.

The menu now reports \`SAVED != ACTIVE\` instead of a false \`A3 VERIFIED\`
when mode 1 has been saved but the FPGA is still in mode 0. It also
recommends \`RESTART MCU\`. The end-of-boot log repeats a concise status:

    AUDIOCFG S=1 FPGA=A1 RT=D1 OK

**Test:** update the FPGA .bin *and* BL616 Stage2 .bin, save Original,
return to Main Menu, choose RESTART MCU (not an Apple keyboard reset);
after boot, verify both the readbacks and dual AY PSG plus SSI263 sound.
Repeat Enhanced -> Original several times and include a cold power-on.
A keyboard Apple RESET alone cannot change the boot mode. Existing
SynthLAB and speech ROMs remain unchanged.

No claim is made of synthesis success or hardware validation of this fix.


## A3-R2: SPI write CS# hold fix (Nov 16, 2026)

Hardware evidence: after A3-R1 boot rearm, console still reports
`AUDIOCFG S=1 FPGA=A0 RT=D0 MISMATCH`. In the same boot session the MCU
printed `SLOTS: EARLY APPLY UNCONFIRMED (DEFERRED...)`. Thus the problem
is *write registration* across the SPI link, affecting mode AND slot-map
commands, not the AY/Ensoniq music mixer.

Source investigation: `fpga_spi_reg_write()` in
`src/a2n20_bl616/firmware/fpga_spi.c` deasserted the manually controlled
SPI CS# immediately after sending the second byte. The FPGA
`bl616_spi_proto_proc.sv` independently synchronizes CS# and the completed
byte toggle into its 54 MHz domain, and its command FSM checks CS# inactive
before processing a pending byte. If CS# rises before the last byte has
crossed its CDC pipeline, the write command is silently discarded. Reads
can still work, explaining the persistent readbacks of A0/D0.

**Fix is MCU-only**: add a 3 us CS# hold after the last byte of each SPI
register write, before deasserting CS#. Apply this to both the normal
thread-safe write and the lock-free fatal-path write. Bulk/XFER behavior
and FPGA RTL are unchanged. Existing A3 FPGA R1 bitstream remains usable.

This is a source-based timing hypothesis supported by multiple boot errors,
not a proven oscilloscope measurement. The hold is approximately 160 FPGA
clock cycles at 54 MHz, comfortably beyond two-flop synchronizers and the
register-write FSM state update. Hardware testing is needed to confirm.

Verify boot with Original already saved and **both** latest MCU binary and
existing A3-R1 FPGA bitstream installed. Expected end-of-boot status:

    AUDIOCFG S=1 FPGA=A1 RT=D1 OK

The `SLOTS: EARLY APPLY UNCONFIRMED` message should also disappear; if
it remains, capture the earliest `AUDIOCFG: ...` log and the final slot
map, and investigate the FPGA SPI proto framing with a cycle-accurate test.


## A3-R3 cold boot vs. warm MCU restart fix

Hardware validation from the user: after using the MCU Main Menu's **RESTART MCU**
action, the machine reports `AUDIOCFG A3: REQ=1 ROUTE=1 OK` and
`AUDIOCFG S=1 FPGA=A1 RT=D1 OK`, and audible dual YM2149 PSG music returns
at a somewhat low volume. An ordinary cold reboot sometimes reports
`AUDIOCFG S=1 FPGA=A0 RT=D0 MISMATCH` and returns to DOC-enhanced music.
This proves the YM2149 source and audio mux work; the remaining defect is
cold-start mode application, not PSG implementation.

Review revealed a two-stage firmware bug:

1. The MCU calls `fpga_spi_wait_ready(2000)`. If this fails during a cold
   power-on, the old audio block unconditionally skips applying settings and
   never retries. Even when the early FPGA status read works, a subsequent
   SPI write may be missed while the peripheral starts.
2. Regardless of whether audio mode was verified, the MCU then writes the
   slot-map commit strobe at SPI register `0x6B`. This also permanently
   locks the FPGA audio mode until a new FPGA boot rearm, locking the
   default Enhanced mode when Original is the persisted selection.
3. Previously `disk_poll()` recovered slot map writes but never reapplied
   the audio mode before it released the Apple II reset.

**A3-R3 fix:** `main.c` uses `audiocfg_ensure_boot_mode()`, which validates
FPGA readiness and the A3 live-route readback, retrying `0x6F = F0` rearm
and the requested mode with bounded settling time. The early `0x6B`
commit is now conditional on **both** verified slots and verified audio.
The final `disk_poll()` boot barrier rechecks audio after USB/storage
initialization, repairs a missed cold-start request, reapplies/verifies
slot assignments if audio rearm occurred, and only then commits `0x6B`
and releases the Apple II reset. If the late operation fails, the console
reports this explicitly rather than silently claiming a selected route.

**Hardware test:** With Original MB saved, perform three complete cold
power cycles (all power sources, including Debug USB disconnected). Verify
`AUDIOCFG EARLY S=1 OK` or `DEFER TO DISK` followed by
`AUDIOCFG S=1 FPGA=A1 RT=D1 OK` on each boot, and listen for real PSG
music + SSI263 speech. Then select Enhanced, save, use RESTART MCU, and
finally return to Original and cold boot again. The dual YM2149 RTL and
HDMI gain calibration are deliberately unchanged in this boot reliability
fix; low-volume AY audio can be calibrated separately after persistence
passes.

The change requires a **BL616 MCU Stage 2 rebuild only**, provided an
A3-R1 or newer FPGA bitstream supporting the 0x6F F0 rearm and 0x6B D0
readback is installed. No overwrite of BL616 Stage 1 at flash 0x0.
Source-level contract checks do not substitute for Gowin synthesis or
hardware verification.


## A3-R4: single-reset cold boot barrier and disk autoboot protection

Reported physical behavior after A3-R3: Original AY mode applies, but on
cold boot the Apple IIe produces two reset sounds and the second reset
interrupts disk autoboot, dropping to the BASIC prompt. This is a startup
protocol defect, not an AY sound-generation defect.

The existing FPGA `RST_MCU_ALIVE_WAIT` (3s) could release /RES while the
BL616 was still booting, and the absolute backstop was 15s. The R3 MCU
then called `audiocfg_ensure_boot_mode()` from `disk_poll()`; on a missed
early mode write this issued `0x6F=0xF0` and reset the already-running IIe.
A warm/keyboard reset is not equivalent to the original power-on autoboot.

R4 changes:

- FPGA no-MCU detection timeout 3s → 12s; MCU-alive failsafe 15s → 25s.
  A truly absent MCU will therefore take longer to release the IIe. This
  is an intentional tradeoff to prevent early startup/autoboot races.
- The MCU checks FPGA status bit5 (`A2BUS_RESET_N`) before *any* automatic
  audio recovery rearm. If Apple /RES is already deasserted it refuses to
  issue a second reset; it reports the unresolved mismatch instead.
- The late `disk_poll()` barrier no longer releases /RES or marks boot
  complete until **both** AUDIOCFG and the slot map are confirmed. On
  transient failures it retries on later polls, until the FPGA's hardware
  safety timeout; it never forces another reset after the Apple has run.
- For a deliberate **Main Menu → RESTART MCU**, the menu first sends
  `0x6F=0xF0` to intentionally put the Apple II into reset **before**
  restarting the BL616 firmware. The subsequent firmware boot can then
  select audio/slots and perform a *single* release for a normal ROM scan.

Test with an actual bootable physical disk in drive 1 or a mounted disk image
and the current A3 project (which implements AudioCFG 0xF0/0x6B). Build and
install **both** FPGA and MCU for this R4 change. Cold power-cycle the IIe,
verify a single reset-release event and no second reset sound, the original
YM2149 audio `S=1 FPGA=A1 RT=D1 OK`, and successful disk autoboot. Then
switch to Enhanced, save and select RESTART MCU; confirm the selected
personality changes without an unexpected reset later during disk work.

R4 is source-implemented only; FPGA timing closure, BL616 compilation and
hardware boot testing are not yet confirmed.
