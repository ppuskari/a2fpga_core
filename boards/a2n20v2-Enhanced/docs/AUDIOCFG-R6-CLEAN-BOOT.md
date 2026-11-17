# AUDIOCFG A3-R6: clean boot recovery

This branch is based on R2 (`4df0d26`), which demonstrated working
Original YM2149 audio after a deliberate MCU restart, **not** on R3-R5's
experimental reset/barrier revisions.

The FPGA and audio cores are unchanged from R2. The BL616 MCU boot
sequencing has been reworked to restore the M641 single reset-release
owner. Save mode 1 once; boot code never writes F0 automatically.

## Hardware register phases

| Phase | Writer | Register | Condition |
| --- | --- | --- | --- |
| 1 FPGA availability | MCU | read 06 | FPGA/SDRAM ready |
| 2 bridge startup | MCU main | 30=1, readback | Apple bus bridge engaged |
| 3 saved audio | MCU main | 6F=0..3, read 6F=A0..A3, 6B=D0..D3 | Before lock; no F0 |
| 4 slot map | MCU main | 60..67 then 6B write=1 | Only after audio and bridge ACK |
| 5 USB services | MCU main | USB host init + disk thread | No Apple reset released yet |
| 6 physical/virtual boot | MCU disk thread | virtual media mount iff virtual Disk II/HDD assigned | Physical drive needs no USB image |
| 7 only reset release | MCU disk thread | 31=1, then 2E=1 with readback | Once; only after mode/slots verified |

If early mode/slots fail, the disk thread retries the missing 30/6F/slot
register writes before releasing Apple reset. There is no runtime F0
rearm, 0x2E write, or CardROM release in main(). The FPGA retains its
original 3-second no-MCU and 15-second emergency release fallback,
not intentionally used during normal boot.

A direct manual Main Menu -> RESTART MCU sends F0 once, asserting Apple
reset and unlocking the FPGA, and only then restarts BL616 firmware.
This is not the automatic cold boot path.

### Verify on physical IIe

1. First recover from the R5 blank-screen state if necessary by flashing
   a known-good Stage 2 image via the UPDATE ROM bootloader (no Stage 1).
2. Compile R6 MCU with the BL616 SDK v2.3.27. FPGA rebuild is unnecessary
   if the installed FPGA already has the compatible R2/R5 A3 audio RTL.
3. On cold boot with Original saved, verify one startup sequence, audio
   0x6F=A1 and active-route 0x6B=D1, normal physical disk autoboot,
   and dual YM2149 + hybrid SSI263 audio.
4. Repeat after complete power removal. Switch to Enhanced and back
   using Save then deliberate Main Menu -> RESTART MCU.
5. Confirm USB keyboard and menu, disk image selection, audio startup,
   normal late disk service and no second reset.

Caveats: source contract tests cannot guarantee Gowin timing, BL616
cross-compilation, or real hardware behavior. Do not merge into MB6.6
or distribute until hardware validation passes. Preserve last known-good
M641 binary and FPGA image separately.
