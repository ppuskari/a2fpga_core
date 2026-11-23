# M3 Apple/IIgs-first HDMI startup (experimental Stage2 policy)

Branch: `petar/m3-mb-timing-prodos-suite-20261123` only.
Production M3 `petar/m3-sd-sector-burst-20261123` is unchanged.

## Root cause of variable perceived boot order

The FPGA **already** resets `video_enable_r` to 0, selecting normal
Apple II/IIgs video. Headless Gowin Tcl generation sources the same HDL,
Gowin device, pins and timing constraints as the `.gprj`; it does not
set a video boot preference.

In the BL616 Stage2 host firmware, the storage initialization routine
`disk_remount()` historically called `osd_console_show()`, asserting
FPGA video takeover via SPI register `0x10`. It scheduled hide after
1.5 seconds on successful disk mount or 180 seconds on missing media.
Apple reset-release/boot timing and disk mounting run independently, so
the console and Apple video could appear in either perceived order,
particularly after changes to IO throughput or FPGA configuration
startup timing. No Tcl-specific change to the video reset default
has been found.

`menu.c` initialized `s_view = VIEW_APPLE` but
`s_mcu_view = VIEW_MENU`, so TAB's first destination was actually the
menu, not the scrollback console. The USB keyboard TAB key is HID usage
`0x2B`, mapped to `XINPUT_BACK`.

## New deliberate policy

- Native IIgs/IIe video is selected from FPGA reset and remains visible
  during *all normal disk mounts and remounts*. `disk_remount()` no longer
  asserts `REG_VIDEO_ENABLE`.
- The disk status/error logs are still buffered in `osd_console` and
  forwarded to the Telnet console. The user can read them any time.
- TAB first opens `VIEW_CONSOLE`. Y switches console/menu. TAB exits
  to Apple video. Subsequently TAB returns to whichever MCU view the
  user last selected.
- The disk task no longer schedules the 1.5s/180s automatic console
  hide, preventing a delayed disk handoff from stealing a user-requested
  console/menu view.
- Emergency short-read diagnostics still use their pre-existing
  `osd_console_show()` call so critical storage faults remain visible.
- Media mounting, early slot mapping, Apple /RESET release, MOD, DOC,
  SSI263, SPI audio throughput and FPGA video reset are unchanged.
- If no storage is found, Apple video remains visible; press TAB for
  detailed error messages rather than waiting for an automatic overlay.

Only `firmware_host/disk.c` and `firmware_host/menu.c` change.
There are **zero FPGA HDL, LUT, DSP or block-RAM changes** for this policy.

## Build/deploy

Use the existing isolated checkout:

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-m3-hdmi-lab
git pull --ff-only
.\M3.ps1 Build
.\M3.ps1 Flash
.\M3.ps1 CheckRuntime
```

**MCU BL616 Stage2 only (0x40000).** No FPGA rebuild, FPGA SRAM reload,
or Stage1 update is needed for this display-default correction.
The existing M3.ps1 branch/commit/SHA256 guards remain active.

Regression `boards/a2n20v2-Enhanced/tests/test_m3_apple_first_boot.py`
checks all expected reset, takeover, TAB and diagnostic-buffer contracts.
It runs in the experiment's GitHub Actions workflow; it is a
source-level check and cannot substitute for physical USB keyboard
or HDMI cold-boot validation.

## Hardware checks

1. Power cycle with the known-good M3 experimental FPGA.
2. See native IIgs ROM/video and GS/OS boot directly, with no brief
   MCU log takeover during routine storage mounts.
3. Press TAB: OSD console logs show the entire stored startup history.
4. Press Y: full menu opens, including MOD browser.
5. Press TAB: native IIgs video returns; TAB again returns to menu.
6. Let MOD audio play while toggling; audio output and SD-burst
   performance should remain identical.
7. If storage intentionally fails/missing, TAB still reveals the
   mount error in the buffered console.
