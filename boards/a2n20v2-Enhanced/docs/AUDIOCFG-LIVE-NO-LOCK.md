# A3: live audio mode without boot lock

This branch starts from the latest M641-safe MCU firmware and overlays
the four A3-R2 RTL files: Enhanced top.sv, bl616_spi_connector.sv,
sound_glu.sv and mockingboard.sv. The only modified A3 RTL logic
removes the 2-bit mode's boot lock. No reset-controller timing, slot
routing or audio-engine processing changes.

* 0x6F WRITE 0..3 sets Enhanced, Original, Native DOC or Shared live.
* 0x6F READ returns 0xA0|mode, 0x6B READ reports active D0|mode.
* 0x6B WRITE still commits virtual slots; it no longer locks audio.
* Legacy 0x6F WRITE F0 is retained for explicit Apple boot rearm only.
  No MCU audio mode operation or menu restart invokes F0.

MCU AUDIO CONFIG > SAVE + APPLY AUDIO first saves mode to flash and
then writes the mode to the FPGA and checks both 0x6F and 0x6B.
No MCU, Apple IIe, FPGA or Disk II reset is needed. Existing music
may need the Apple program restarted to reinitialize its voices.
Power-on also applies the persisted mode normally before slots.

Both updated FPGA bitstream and BL616 Stage2 MCU firmware are needed.
An MCU-only flash cannot remove the older A3 FPGA RTL's audio lock.
Retain known-good M641 and A3 binary images for rollback. Fused
BL616 Stage1 at 0x0 MUST NOT be modified: MCU Stage2 is at 0x40000.

Source-only tests: tools/test_audiocfg_m641_boot.py and
tools/test_audiocfg_live_mode.py. Gowin synthesis/PnR, BL616
cross-compilation, real cold-boot and AY/DOC audio checks pending.
