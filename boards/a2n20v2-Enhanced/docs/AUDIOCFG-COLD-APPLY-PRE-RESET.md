# Audio CFG: cold-boot flash mode reconciled at verified pre-release SPI

Branch: `petar/audiocfg-cold-apply-pre-release-20261117`

## Hardware diagnosis

- Cold FPGA defaults to Enhanced DOC (A0/D0).
- BL616 flash correctly reports the saved Original AY (1).
- Early `main.c` 0x6F selection sometimes fails to take effect; existing
  M641 disk code explicitly documents **lost early SPI writes**.
- Selecting and SAVING Original AY in the running MCU menu reliably writes
  0x6F=A1, returns 0x6B READ=D1, and plays AY *without Apple reset*.
- Original AY volume from the SynthLAB + AY-gain branch is validated
  on hardware; DO NOT change it. Live mode switching likewise works
  even during music playback.

## Minimal fix

1. `main.c` after `settings_init()` calls
   `menu_audio_apply_saved_early()`: unconditionally write the persisted
   mode to A3 0x6F and verify *both* 0x6F=A0..A3 and active 0x6B=D0..D3
   up to 16 times. This is before M641's original slot commits.
2. In unchanged M641 disk flow, after successful medium mount
   (or no-media seven-second deadline), and before `REG_CARDROM_REL`
   and `A2_RST_RELEASE`, call
   `menu_audio_apply_saved_before_release()`.
   By that time the disk service has proven reliable SPI operation.
   Same 16 retries/readback. This happens once, never during later
   filesystem remounts or music playback.
3. Keep the verified live menu save path *unchanged*.
4. Preserve boot snapshots in AUDIO CONFIG menu:
   `FLASH SAVED`, `BOOT CONFIG SOURCE`,
   `BOOT EARLY SPI`, `BOOT PRE-RESET`,
   `FPGA BOOT REQUEST`, `FPGA ACTIVE AUDIO`,
   `FPGA ROUTING`. Format e.g. `S1 A1/D1 OK`
   for saved mode 1, accepted mode A1, active D1, success.
   The diagnostics remain readable after console lines scroll.

This fix never writes 0x6F=F0, never changes slot 0x6B write,
never asserts Apple /RES, changes no FPGA RTL and no DOC/AY/SSI263
audio or gain. The only added disk.c activity is the verified A3
mode write/read before M641's original CardROM/reset-release sequence.

**MCU Stage2 ONLY**, FPGA build/bitstream already hardware-proven
for live switching and AY levels; retain it.

## Validation

Run:
`py -3 tools/test_audiocfg_m641_boot.py`
`py -3 tools/test_audiocfg_live_mode.py`
`py -3 tools/test_audiocfg_cold_apply.py`
`py -3 tools/test_audiocfg_samples_gain.py`

Check on cold power-off/on: FLASH SAVED=ORIGINAL MB,
BOOT EARLY SPI and BOOT PRE-RESET snapshots, active A1/D1,
physical Slot6 autoboot and AY music immediately without
manual Save. Then switch Enhanced and back live without an
Apple reset; SSI speech still works.

If EARLY=BAD and PRE-RESET=OK the specific startup timing
hypothesis is supported. If PRE-RESET=BAD, inspect SPI and FPGA
readback before attempting further changes.

Static tests/source assertions cannot replace BL616 compilation,
real reset/bus timing and actual hardware testing.
