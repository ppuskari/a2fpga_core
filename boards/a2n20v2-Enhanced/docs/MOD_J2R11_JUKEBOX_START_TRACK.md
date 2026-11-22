# J2R11: Start the MOD jukebox from any selected song

**Base:** J2R10 quiet-console firmware (which itself is based on J2R9B's proven
8-channel playback). The PCM FIFO, +8dB stereo limiter, 16KiB pattern cache,
8 × 8KiB sample cache with 4 × 2KiB LRU windows, J2R9B SPI settings, and
audio gain are **not modified**.

## New UI workflow

Open the MCU menu and navigate to **MCU MOD PLAYER**. The additional actions
are:

- **JUKEBOX START AT .MOD** — opens the existing 48-per-page MOD file picker
  in a new mode. Browse into any directory, move through pages, and
  select the MOD file you want to hear **first**. The MCU scans *that file's
  parent folder*, sorts the MODs case-insensitively by full relative path
  using the existing jukebox ordering, and starts from the selected file.
  Playback continues to the end of the folder's playlist, not back to its
  first track. For example, with an alphabetically sorted 50-file
  directory, selecting number 28 plays 28, 29, ... 50.
- **RESUME LAST JUKEBOX TRACK** — after pressing **STOP PLAYBACK**, replays
  the last playing jukebox track *from the beginning*, then continues
  through the remainder of the playlist. This shortcut works **as long
  as the MCU remains powered on** and the playlist has not been replaced.
  It does **not** resume in the middle of a MOD.
- **BROWSE .MOD FILES** — retains its existing **single-file** playback
  action. Existing **JUKEBOX LAST FOLDER**, **JUKEBOX LAST FOLDER+SUBDIRS**,
  and **JUKEBOX: THIS FOLDER** behaviors still start from the first track.

### Later listening sessions

After a physical power cycle, the in-RAM playlist is gone. Use
**JUKEBOX START AT .MOD** and pick the last song you remember.
This feature deliberately does not constantly erase/write the
last BL616 flash settings sector, which would impose flash wear and
potential playback delays. Automatic cross-reboot bookmarking is not
included in this release; the selected-file restart works without it.

## Implementation and safety

- A new `s_juke_start_file` is copied atomically with the existing
  directory request via the original seqlock. The disk/MOD worker, never
  the UI thread, scans the folder and loads HxCMOD. No extra filesystem
  concurrency or SPI calls are introduced in the audio render loop.
- `mod_jukebox_find()` performs a **full-path** case-insensitive exact
  match on the already sorted catalog. The chosen file may be on page
  2, 3, ... of the picker; its index is resolved from the catalog itself,
  rather than assuming picker pagination matches its sort order.
- If the selected file disappeared between browsing and the scan,
  the player reports **START MISSING** and does not silently restart
  at track 1.
- Track completion continues sequentially to the end, preserving the
  existing play-once semantics; **NEXT** and **PREVIOUS** still work.
- Source/binary marker **MOD JUKE=STARTFILE** allows the
  dedicated Stage2 PowerShell script to reject older binaries.

## Windows PowerShell build / Stage2-only flashing

Clone separately; keep J2R10 and the actual J2R9B golden binaries:

~~~powershell
$j2r11="C:\AppleIIgsDev_02\a2fpga-jukebox-j2r11"; git clone --single-branch --branch petar/mod-j2r11-jukebox-startfile-20261122 https://github.com/ppuskari/a2fpga_core.git $j2r11; if($LASTEXITCODE -ne 0){throw "J2R11 clone failed"}
~~~

Build, using auto-discovered Bouffalo SDK/make/gcc tools:

~~~powershell
Set-Location $j2r11; .\J2R11.ps1 Build
~~~

After a successful build, enter BL616 **BootROM UPDATE** mode and flash
**MCU Stage2 at offset 0x40000 only**:

~~~powershell
.\J2R11.ps1 Flash
~~~

The script requires the J2R11 branch, current source fingerprint,
compiled binary signature, and explicit typed confirmation. No FPGA
reflash, Stage1 flash, A3 settings reset, DOC patch or SDRAM-map change.

On startup check the advanced console includes:

    MOD SMP WIN=4x2048B
    MOD SPI=PCM512 SDRAM=BYTE
    MOD LOG=QUIET1HZ
    MOD JUKE=STARTFILE

## Acceptance on Apple IIe / Tang Nano 20K

1. Select an ordinary MOD with **BROWSE .MOD FILES**, verify it is still
   single-track playback, gain/limit and navigation unchanged.
2. Choose **JUKEBOX START AT .MOD**, navigate to a folder with multiple
   files, select a **middle** song on page 1 or page 2. Confirm "NOW
   PLAYING" reports its sorted position (e.g. **28/50**), not 1/50.
3. Let a track end naturally; verify it plays the **following** sorted
   file, without jumping backward to the first.
4. Press **STOP PLAYBACK**, later select **RESUME LAST JUKEBOX TRACK**;
   the last song restarts from its beginning and advances normally.
5. Test **NEXT**, **PREVIOUS**, and ordinary **JUKEBOX LAST FOLDER**
   to ensure legacy behavior is preserved.
6. Play `3EDGES.mod` and `CHEER.MOD` with normal Apple IIe video
   showing. J2R9B baseline is **UDR=0** for both demanding 8-channel
   modules; no PCM/audio changes are intended.

## CI vs hardware

Host tests cover sorted playlist lookup, exact case-insensitive path
match, missing-file behavior, the existing MOD filesystem interface,
and source-level menu dispatch. Prior J2R10 console/SSI simulation
regressions and J2R9B MOD PCM regressions are inherited. Native
Bouffalo firmware compilation and physical jukebox usage are still
needed before release.
