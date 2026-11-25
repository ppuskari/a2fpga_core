# M3 advanced console — isolated post-release 80-column Stage2 experiment

Branch: petar/m3-advanced-console-80col-20261124
Base: hardware-validated M3 565df1d1704b7fb4b5d7f5522297fc2ceebbd736
Stable release: m3-2026.11.24 MUST remain unchanged.

## Intent

Make the TAB-accessed MCU console readable at 80 columns without touching
the stable FPGA or modifying the existing 40-column MCU menus. The reported
MCU JUKE LOW HEAP FOR TRACK 494 (CHUNKS=...) is already emitted by firmware;
the previous 39-character vsnprintf() permanently discarded its trailing
chunk count before either HDMI or Telnet could show it.

## Implementation

- The existing Enhanced FPGA supports register 0x17 (COL80), 0x10
  (video takeover) and 0x11 (TEXT_MODE). No RTL or FPGA rebuild required.
- The MCU fpga_screen.c supports 80 screen codes per row in the same 2 KiB
  physical Apple text-page allocation: row offset is
  0x50*(y>>3) + 0x100*(y&7). At 40 columns each screen code occupies an
  even byte with A0 padding; in 80 columns both even and odd bytes contain
  glyph codes. Its partial-write path reconstructs aligned 32-bit words
  from the SRAM shadow to avoid dropped SDRAM word accumulator writes.
- The diagnostic console keeps a 23-line backlog with 79 printable
  characters per line. One spare column avoids unwanted auto-wrap.
  It repaints at most once per second from the menu/HID task only.
  osd_log() never performs SPI transfers.
- VIEW_CONSOLE selects 80-column writer, repaints and enables COL80=1.
  VIEW_MENU switches to 40-column software writer and COL80=0 before
  repainting the unchanged menu. Returning to Apple disables video takeover.
- Telnet has only an 8-line live queue at 79 columns, with no new
  scrollback feature. Its menu mirror uses the current screen width.

## Resource impact

OSD log ring grows from 23x40 to 23x80 static bytes, Telnet tee shrinks
from 32x41 to 8x80 static bytes, screen shadow grows 24x40 to 24x80.
No extra heap allocations or FreeRTOS tasks are introduced.

## Tests

On each branch push, workflow m3-advanced-console-80col.yml verifies:
1. Real MCU C against an in-memory 2KiB OSD SDRAM model: 40-column
   even-byte packing, 80-column packed layout, aligned complete-word
   SPI writes, partial character writes, and full log records.
2. Legacy J2R10 batching, lockout, throttled repaint and Apple handoff.
3. Menu/console COL80 control and runtime Telnet mirror width.

CI does NOT constitute a real Bouffalo SDK build or hardware validation.

## Build from a separate Windows PowerShell 5.1 worktree

Do not switch branches or build inside the known-good
C:\AppleIIgsDev_02\a2fpga-m3-hdmi-lab tree. Keep its compiled
FPGA and Stage2 files unchanged.

    git -C "C:\AppleIIgsDev_02\a2fpga-m3-hdmi-lab" fetch origin
    git -C "C:\AppleIIgsDev_02\a2fpga-m3-hdmi-lab" worktree add --track -b petar/m3-advanced-console-80col-20261124 "C:\AppleIIgsDev_02\a2fpga-m3-console80-lab" origin/petar/m3-advanced-console-80col-20261124
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\AppleIIgsDev_02\a2fpga-m3-console80-lab\M3.ps1" Build

Use the original M3-release FPGA .fs; no new gateware required. The
first hardware test sequence: TAB -> 80-col console; Y -> 40-col menu;
Y -> 80-col console; TAB -> native Apple video. Then test MOD playback,
folder scanning and audio underruns. Confirm that complete track/chunk
OOM diagnostics are readable.

If you choose to flash the experimental Stage2, use the guarded M3.ps1
Flash command from the console80 worktree. Stage2 offset is 0x40000
ONLY. Never touch signed Stage1 at 0x00000. The stable three-file
release remains the fallback, unchanged.

## Limitation

Actual Apple IIe/IIgs HDMI rendering and a complete BL616 SDK
cross-compilation must be confirmed on hardware before this branch is
considered hardware-validated.
