# SenseiPlay8 P2W — NinjaTrackerPlus v2 import (non-streaming)

**Status:** MCU Stage 2 source and portable regression fixtures committed.
Hardware audio and the complete BL616 cross-build are **not yet verified**.
P2V remains unchanged.

- Branch: `petar/sensei8-p2w-ntp-v2-import-20261119`
- Parent: `petar/sensei8-p2v-ntp-sample-bypass-20261119`, SHA `c7f8246ae8e0c76b18d3fdf59617c609e1a9b39d`
- Hardware: a2n20v2-Enhanced Tang Nano 20K + BL616; preserved P2S/P2U FPGA Native DOC mode.
- No FPGA HDL changes, no new ProDOS SYS, no change to the known-good A3 persistent audio selection, no change to MOD decoding.

## Why

The NinjaForce web-based converter produces NTP **version 2**. P2V imported only
historical version 0. Two real v2 files provided by the project owner were
inspected independently:

| Module | Raw size | Tracks | Instrument records | Patterns | Orders | PCM bytes | DOC high water | Streaming |
|--|--:|--:|--:|--:|--:|--:|--:|--|
| `15k(1).ntp` | 16,167 | 4 | 13 | 6 | 6 | 9,607 | `$2A00` | None |
| `1_minute_dead_waltz(1).ntp` | 12,121 | 4 | 1 | 6 | 15 | 5,886 | `$1700` | None |

Both contain only zero-finetune instruments. They are not redistributed in
this repository: copy your source files directly to the FAT32 USB/SD `MODS`
folder, naming them `15k.ntp` and `1_minute_dead_waltz.ntp` if preferred.

## Format handling

The NTP v2 header uses the original `nfc!` magic, version byte `2` at
offset 4 and original track/instrument/pattern/order counts at offsets 5–8.
After that come a length-prefixed song title, three bytes for each track
(output route, stream-buffer page, original oscillator allocation),
then variable-length instrument records (15-byte fixed header plus
length-prefixed name). Each instrument record describes:

- type, 24-bit little-endian audio length, 24-bit original repeat position,
  24-bit original repeat length, volume, signed finetune, DOC sound RAM page,
  DOC wavetable-size register, and length-prefixed instrument name

The order table, uncompressed 64-row pattern records, and DOC-ready waveform
bytes follow. P2W translates pattern note numbers into the existing four-voice
P2U tick-engine format and copies the **actual converted DOC sample bytes
without modification**. No XOR, resampling, repacking, or sentinel rewriting.
The song/instrument names are only skipped after bounds validation.

P2W deliberately rejects v1, streaming sample types and nonzero stream-buffer
pages, any channel count other than four, instrument finetuning other than
zero, overlarge DOC sample placement, overlapping DOC pages, and unsupported
P2U effects. As before, complex nonideal split-loop IRQ retargeting is not yet
equivalent to the original NTP 65816 player.

Sources for format comparison (not bundled):
- https://github.com/antoinevignau/source/tree/master/ntpsources
  (original v0 documentation, PHP converter, 65816 player)
- https://github.com/polluks/PETSCIIRobots-IIgs/blob/master/ntpconverter.c
  (v2 converter implementation; `save_ntp` explicitly serializes records)

## Portable regressions

`test_p2v_ntp_import.c` remains the historical synthetic v0 regression.
New `test_p2w_ntp_v2.c` constructs a self-contained v2 fixture and checks
metadata offsets, 3-byte track records, 15-byte+name instrument records,
waveform byte equality, pattern conversion, and rejection of unsupported
or truncated input. GitHub workflow
`.github/workflows/sensei-p1d-transport.yml` runs both import tests.

Portable standalone command, from the repository root:

```sh
gcc -std=c11 -O2 -Wall -Wextra -Werror \
  -Iboards/a2n20v2-Enhanced/src/a2n20_bl616/firmware_host \
  boards/a2n20v2-Enhanced/tests/test_p2w_ntp_v2.c \
  boards/a2n20v2-Enhanced/src/a2n20_bl616/firmware_host/sensei_ntp_import.c \
  -o /tmp/test_p2w_ntp
/tmp/test_p2w_ntp
```

## Windows PowerShell 5.1 — build and deploy Stage 2 ONLY

Clone to a new worktree to keep P2V and all golden references intact:

```powershell
$hw = 'C:\AppleIIgsDev_02\a2fpga-sensei-p2w'
if (-not (Test-Path "$hw\.git")) { git clone --branch petar/sensei8-p2w-ntp-v2-import-20261119 --single-branch https://github.com/ppuskari/a2fpga_core.git $hw }
git -C $hw fetch origin petar/sensei8-p2w-ntp-v2-import-20261119
git -C $hw switch petar/sensei8-p2w-ntp-v2-import-20261119
git -C $hw pull --ff-only
git -C $hw log -1 --oneline
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
cd "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host"
make -j4 CHIP=bl616 BOARD=bl616dk
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin
Get-FileHash .\build\build_out\a2n20_bl616_host_bl616.bin -Algorithm SHA256
```

After a successful local cross-build, flash **only Stage 2**:

```powershell
cd "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616"
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

**Never** run `make flash`. Do not modify signed Stage 1 at `0x0`.
Stage 2 is at `0x40000`. Leave the P2S/P2U FPGA image in place.

## Hardware A/B validation

1. Confirm boot menu still obeys the persistent Native DOC audio choice.
2. Keep the same HDMI extractor/cables and use the MOD LIBRARY on FAT32.
3. Play original `15k.mod`, record audio and MCU/FPGA counters.
4. Play `15k.ntp` converted by the web converter, same signal chain.
5. Repeat with `1_minute_dead_waltz.ntp`. Record whether it completes all
   song positions, including order jumps and pattern loops.
6. Repeat per-channel audition CH0 / CH1 / CH2 / CH3. The original NTP
   output routing is honored, which may differ from the MOD default.
7. Capture `SENSEI P2W: NTP V2 DOC PCM DIRECT` and any
   `P2V NTP NONIDEAL LOOPS=N` log; note click/pop and loop continuity.
8. Check FPGA FIFO overflow `OVR=0` and MCU staging overflow absent.
9. Cold reboot to confirm A3 flash-selected audio personality remains correct.

**Do not treat the v2 importer passing as evidence of full NinjaTrackerPlus
music-engine parity.** NTP effect handling still uses the P2U C engine;
nonideal sample loop IRQ/rearm behavior is a subsequent phase.
