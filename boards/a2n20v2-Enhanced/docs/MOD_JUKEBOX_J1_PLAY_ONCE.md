# J1 — direct-HDMI MOD Jukebox, natural end-of-song, NEXT/PREVIOUS

Branch: `petar/mod-jukebox-j1-20261121`
Base: hardware-validated `petar/media-mailbox-m1-slot3-console-20261120` (M1).

**J1 is BL616 Stage 2 firmware only. The FPGA bitstream is unchanged.**
The real-hardware M1 zero-underrun 44.1-kHz HDMI PCM and physical-slot-3
mailbox are retained, along with IIgs DOC, Mockingboard, SSI263, A3 modes,
Apple boot behavior and other SPI spaces.

## Behavior

- **Single .MOD selected manually:** existing continuous repeat by default.
  Toggle **SINGLE MOD PLAY ONCE** to stop after one order-list pass.
- **Jukebox folder:** play all .MOD files in a selected FAT folder, once each,
  case-insensitive alphabetical order. Stop after the final song.
- **Jukebox tree:** likewise recursively include subfolders.
- **NEXT/PREVIOUS:** change songs immediately in the active jukebox playlist;
  explicit NEXT from the final track wraps to first, explicit PREVIOUS from the
  first wraps to last. Automatic end-of-song advancement does NOT wrap the list.
- A song's completion is detected by HxCMOD's new `song_wraps` counter on
  natural order-list wrap or ProTracker backward Bxx/Dxx order jumps.
  A single-order MOD is handled. Normal ProTracker E6 pattern loops remain
  effects within the song. Intentional infinite song loops are treated as an
  end marker when they jump backwards in the order list; a degenerate
  E6-only infinite loop has no natural end-of-song marker.
- The BL616 waits for the FPGA PCM FIFO to drain before advancing. A boundary
  may produce an expected underrun counter increment; continuous playback
  within a song should still maintain UDR=0.
- Playlist limits for this first field build: **512 MOD paths, 96 directories,
  paths under 128 bytes**, and existing **192 KiB MOD file** limit. Limits
  produce `MCU JUKE: ... (LIMIT)`; this mode does not promise to cover
  libraries exceeding the cap. Files that fail decoding/loading are skipped.
- FAT enumeration uses its own private directory handle, served by the
  disk thread; FTP listing and MOD read handles are unchanged.
- No NTP, DOC translation, ROM, or slot ROM was introduced.

## MCU keyboard/menu

TAB -> MENU -> MCU MOD PLAYER -> **BROWSE .MOD FILES**.
Select a folder then choose `(JUKEBOX: THIS FOLDER)` or
`(JUKEBOX: WITH SUBFOLDERS)`. The same choices work at the volume root.
Selecting a file plays just that file, as before.

Other options on the MOD PLAYER page:

- `JUKEBOX LAST FOLDER` (uses folder of last successfully loaded MOD, or root)
- `JUKEBOX LAST FOLDER+SUBDIRS`
- `NEXT MOD`, `PREVIOUS MOD`, `STOP PLAYBACK`
- `SINGLE MOD PLAY ONCE` (ON/OFF; for manual single-song playback)

Console logs: `MCU JUKE: N MODS FOLDER/TREE`,
`MCU JUKE: TRACK x/N`, `MCU MOD: SONG COMPLETE (ORDER WRAP)`,
`MCU JUKE: FINISHED / PLAY ONCE DONE`.

## Telnet port 23 (console view)

`j`: jukebox last song's folder; `J`: folder and subfolders.
`n`: next; `N`: previous. `1`: manual single-song play once;
`0`: repeat manual track; `k`: stop MOD. `p`/`P` retain M1 probe/selftest.

## Apple IIe / IIgs mailbox, physical slot 3

J1 reuses **$C0B4 = 49332**. No FPGA recompile.

| POKE 49332,N | Action |
| --- | --- |
| 1 | Ping ($A5 PONG) |
| 2 | Replay last selected/current MOD |
| 3 | Stop |
| **4** | Jukebox last selected MOD's folder (or FAT root) |
| **5** | Jukebox that folder and all subfolders |
| **6** | Next |
| **7** | Previous |
| **8** | Manual single MOD: play once |
| **9** | Manual single MOD: repeat continuously |
| 16 / 17 / 18 | Existing M1 diagnostic BEGIN / END / ABORT |

Poll command sequence/ack via `PEEK(49338)` and `PEEK(49339)`,
then read result at `PEEK(49340)`: `0` for accepted action, `226`
($E2) for NEXT/PREVIOUS without a playlist. Acknowledgment means the
request was queued, not that the file scan or load finished; watch console.
The mailbox's existing diagnostic FIFO/protocol are unchanged.

## Windows PowerShell 5.1 — MCU-only isolated build

This keeps the **working M1 checkout**, all instrument/SSI ROM files and
the golden FPGA flash intact. There is **no FPGA preparation/synthesis** for J1.

```powershell
$j1 = 'C:\AppleIIgsDev_02\a2fpga-jukebox-j1'
if (-not (Test-Path "$j1\.git")) { git clone --branch petar/mod-jukebox-j1-20261121 --single-branch https://github.com/ppuskari/a2fpga_core.git $j1 }
git -C $j1 fetch origin petar/mod-jukebox-j1-20261121
git -C $j1 switch petar/mod-jukebox-j1-20261121
git -C $j1 pull --ff-only origin petar/mod-jukebox-j1-20261121
git -C $j1 log -1 --oneline
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
Set-Location "$j1\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host"
make -j4 CHIP=bl616 BOARD=bl616dk
if ($LASTEXITCODE -ne 0) { throw 'J1 MCU compile failed - do not flash' }
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
Get-FileHash .\build\build_out\a2n20_bl616_host_bl616.bin -Algorithm SHA256
Set-Location "$j1\boards\a2n20v2-Enhanced\src\a2n20_bl616"
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

**Never** run `make flash`. Preserve the vendor-signed Stage 1 at
0x00000; only update BL616 application Stage 2 at 0x40000.
Keep loading the already-tested M1 FPGA image into volatile SRAM if necessary
after any power cycle. J1 does not change that image.

## Test sequence

1. Boot with the hardware-validated M1 FPGA image and J1 MCU Stage2.
2. Play a known-good manually selected MOD with `SINGLE MOD PLAY ONCE=OFF`:
   expect continuous looping and UDR=0 within the song (M1 baseline).
3. Toggle ON and replay the same song: expect one full order-list pass then
   STOP, including one-order MODs.
4. Navigate to a FAT folder containing 2+ MOD files. Choose
   `(JUKEBOX: THIS FOLDER)`. Expect sorted, one-pass automatic transitions
   and a stop at the final track.
5. Repeat with `(JUKEBOX: WITH SUBFOLDERS)` and songs in child directories.
6. Exercise NEXT/PREVIOUS during playback from menu, Telnet and IIe POKE.
7. Exercise `POKE 49332,4` and `POKE 49332,5` from the IIe, check
   sequence/ACK and console track logs. Test IIgs after IIe.
8. Confirm original DOC/Enhanced Mockingboard/SSI263 playback unaffected.
9. If a regression occurs, restore the known-good M1 MCU Stage2 .bin;
   J1 does not require any FPGA flash changes.

CI compiles host code using stubs, tests actual HxCMOD C and directory scans,
and runs the preexisting M1 FPGA simulations. It does not substitute for
BL616 SDK cross-compilation or physical audio testing.
