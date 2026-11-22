# M2 — A2MEDIA bidirectional FAT jukebox browser

Status: EXPERIMENTAL, physical hardware validation required. Base J2R11 at
commit a984abcfb03ef87554c9bf21ea26b6ddb84e7441 is golden and unchanged.
Separate Apple application branch: ppuskari/a2media.system,
petar/m2-80col-fat-picker-20261122.

## Preserved M1 interface

Physical slot-3 Apple addresses $C0B0–$C0BF, ROMless. Version remains 1;
signature M,B,1; P0 A2MEDIA and legacy M1 commands work unmodified.

$C0B4 writes commands; $C0BA sequence, $C0BB ACK, $C0BC result.
$C0B5 Apple WRITE still appends to Apple->MCU FIFO (256 bytes).
$C0B5 Apple READ newly returns one MCU->Apple reply FIFO byte (256 bytes).
Status $C0B3 bit7 REPLY_READY is new. FPGA holds a reply byte stable for an
entire Apple bus phase and pops it AFTER Apple /SEL drops.

MCU SPI7 write $800030 pushes one reply byte; write $800031 with $A5 clears
reply FIFO; read $80001A/1B reports reply count; read $80001C overflow;
read $80001D/1E returns ASCII M,2. MCU refuses new M2 commands if this FPGA
M2 probe fails, so upgrading Stage2 without upgrading gateware is detectable.
Space 6 audio PCM and the entire HxCMOD/gain/samples/A3 chain are unchanged.

## Added M2 commands

- $20 CAPS: result $02 if M2 FPGA found, $E8 otherwise
- $21 ARM: clear request and old reply, start accepting request string
- $22 OPEN_DIR: open path supplied after ARM; result $00/$E6/$E7
- $23 NEXT_ENTRY: return one directory entry, or $D0 EOF
- $24 CLOSE_DIR: close Apple UI FAT iterator
- $25 PLAY_FILE: queue selected MOD
- $26 JUKE_START_FILE: scan parent and begin at selected MOD, J2R11 sorted index
- $27 RESUME_JUKE: resume stopped playlist
- $28 GET_SOURCE: reply [1,0=SD/1=USB]
- $29 GET_STATUS: reply [5,state,lastLO,lastHI,totalLO,totalHI]
- $2A GET_NOW_PLAYING: reply [1+n,active,basename ASCII n], n=0..63. The basename is read from the same generation-stable snapshot as the MCU console. Returns $EA if publication overlaps the snapshot; Apple retries at its next periodic poll. When inactive, reply [1,0]. No new FPGA registers are required.

A pathname request is ARM, then NUL-terminated relative ASCII path bytes
through Apple writes to $C0B5, then OPEN_DIR / PLAY_FILE / JUKE_START_FILE.
Root folder path is a single zero byte. Max 127 bytes including NUL.
Reject absolute paths, dot-dot traversal, drive prefixes and backslash.
The ARM request assembler handles bytes received over multiple MCU polls.

Each NEXT_ENTRY reply consists of [length][type][name characters], where
length=1+nameLength, type=1 for folder and 0 for MOD. Names are 1..63
ASCII bytes, not NUL-terminated. WAIT for ACK before reading, then read
exactly length+1 bytes from $C0B5. $C0B3 bit7 indicates data ready.
Directory enumeration is now a complete, case-insensitively sorted folder
snapshot (not page-local and not raw FAT order): folders first, then .MOD files.
The MOD filename ordering matches the existing J2R11 jukebox's case-insensitive
sort, including across 12-entry Apple pages; chosen paths still resolve to
their correct playlist index. The Apple browser owns its own catalog and does
not alias the live jukebox catalog or FAT handles. The directory scan is
bounded at 512 visible entries (folders + MODs); OPEN returns $E7 instead of
silently truncating an oversized directory or a failed allocation. Apple
displays the 16-bit jukebox position/count in five-digit decimal fields.

All FAT ops execute in the existing disk thread. A new g_media_dir FAT
handle is entirely separate from both FTP's directory and J2R11's
jukebox directory. The BL616 mailbox task builds the sorted browser
catalog by requests to that dedicated FatFS handle, then closes the directory
before serving paginated Apple reads from the independent catalog. The selected
FAT backend (SD/USB) is not remounted.

## Windows isolated test build (no golden flash updates)

PS> $m2="C:\AppleIIgsDev_02\a2fpga-media-m2"
PS> git clone --single-branch --branch petar/media-m2-bidir-fat-picker-20261122 https://github.com/ppuskari/a2fpga_core.git $m2

Start with the complete ROM and piano preparation (one command):

PS> Set-Location $m2
PS> .\Build-M2-FPGA.ps1 Prepare

All SSI263 voice/parameter tables are committed and checked. The authentic
seven-zone Apple SynthLAB piano ROM is automatically downloaded and verified
if missing. No manual voice/piano ROM copying is required with network access.
For an offline clean build, use -Offline -SynthLABDisk <original-synthLAB.po>.
Full instructions: docs/ENHANCED_FPGA_ROM_ASSETS.md.

Open:
  C:\AppleIIgsDev_02\a2fpga-media-m2\boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj

Alternatively run .\Build-M2-FPGA.ps1 Build -GowinCli <gw_sh.exe>.
Synthesize/place/route in Gowin and program FPGA VOLATILE SRAM ONLY.
Do not replace golden FPGA flash. M2 duplicates a 2KiB reply buffer;
the actual Gowin resource utilization/timing remains to be measured.

PS> Set-Location $m2
PS> .\M2.ps1 Build

With BL616 in BootROM UPDATE mode, flash ONLY MCU Stage2 at 0x40000:

PS> .\M2.ps1 Flash

Script validates source and binary SHA256 and requires M2 FAT REPLY=YES,
MOD JUKE=STARTFILE, MOD LOG=QUIET1HZ, 2KiB sample windows, PCM512 and
bytewise FPGA SDRAM signatures. Signed Stage1 and FPGA flash untouched.

## Real-hardware gates

1. On Apple IIe and IIgs, PEEK(49328..49330) still 77,66,1.
2. Old P0 A2MEDIA continues functioning on the new M2 hardware.
3. Boot matching experimental M2 A2MEDIA ProDOS 2.4.3 image.
4. Browse SD root, enter folders and page through MOD files.
5. RETURN on a MOD plays it alone; J starts jukebox from that file.
6. Verify the selected song plays first and its sorted successor follows.
7. Try S/N/P/R transport, B parent, F=previous page, G=next page, I status, Q quit.
8. Verify NOW PLAYING shows the actual MOD basename and changes automatically when jukebox advances (without keyboard input). Then listen to CHEER.MOD while browsing: target zero UDR/ERR and no audible
   interruptions, preserving the proven J2R11 gain and sample cache.
9. IIgs native bus slot-3 behavior must be independently tested.

CI covers Yosys synthesis, Icarus both M1+M2 benches, MCU mocked FAT/SPI
integration, existing HDMI PCM and DOC regressions. It does not prove
Gowin place/route, native BL616 SDK build or electrical bus timing.


### Large ProTracker / Amiga MOD collections (M2 update)

- MCU console directory snapshots now hold up to **512** entries, sorted once
  after a **single** FatFS directory pass (formerly 256 entries and two passes).
  The console has 48-entry pages and a **15-second** bounded scan wait instead
  of 2 seconds, so a ~500-file subfolder is 11 pages rather than a false
  empty result or truncated 256-file list.
- **Cached page navigation:** On first entry into a folder, the disk thread
  builds one sorted catalog of up to 512 entries. The Previous/Next actions
  now copy only 48 records from that in-memory snapshot using
  `disk_list_poll_page`; they never call `disk_list_begin` on a normal
  page change. Entering another folder, navigating to its parent, or reopening
  the picker performs a new scan. If the snapshot is unexpectedly pending,
  paging falls back to a fresh scan rather than showing stale results.
  This removes the multi-second readdir+sort penalty on every page flip.
- Both naming conventions are accepted consistently by the console picker,
  the J2R11 jukebox, direct HxCMOD file selection and the Apple mailbox:
  `SONG.MOD` and classic Amiga `MOD.SONG` (case-insensitive). HxCMOD still
  validates the file header and pattern structure rather than trusting names.
- The console emits `PICK DIR: 0:/... raw=N dirs=N mods=N other=N
  prefix=N long=N rc=N` after each scan. Error status differentiates
  unsupported files, a genuine empty folder, FatFS failure, a timed-out scan
  and a folder exceeding 512 visible entries. Apple mailbox also logs its
  own independent catalog errors.
- This changes BL616 Stage 2 only; the slot-3 FPGA media mailbox ABI, SPI6
  stereo audio, and Floppy Emu's independent slot-6 ProDOS boot path do not
  change. Hardware listing/playback must be verified after flashing.

### Asynchronous Apple II directory scanning (E1 timeout fix)

Large FAT folders (e.g., 506 ProTracker MODs) formerly blocked the MCU
mailbox service inside `MEDIA_CMD_M2_OPEN ($22)` until the complete
directory was read, allocated, and alphabetized. The Apple II's bounded
ACK poll expired with local error `$E1`. The MCU console uses a different,
longer wait, explaining why the same SD card worked from the console.

In this revision, `M2_OPEN` validates and captures the path, then ACKs
without calling FatFS. Each `OPEN`, `NEXT` or `CLOSE` is submitted to the
existing *disk-thread* FatFS broker through a **nonblocking** submit/poll
interface. The MCU mailbox task never waits synchronously for SD I/O and
continues servicing SPI7 commands during a slow sector read. The broker
request has persistent storage until completion; `CLOSE` and replacement
`OPEN` drain pending requests before disposing of an old directory handle.
While the catalog is being built, `M2_NEXT ($23)` returns `M2_RETRY ($EA)`
without a reply FIFO frame. After EOF it sorts the full catalog once.
The Apple II retries `$EA` for up to 32768 command replies, returns
`$EB` for an overall scan-wait limit, and reserves `$E1` for a *single
command ACK failure*. Actual filesystem errors return `$E7`. This does
not modify SPI7 register mappings or the independent SPI6 HDMI PCM path.

**Root-cause correction:** The earlier four-file-per-pass M2 implementation
still called synchronous `disk_fs_request()` four times *inside* the
mailbox task. This caused $E1 on real IIe hardware even while the MCU
console independently navigated the same SD library. Smaller chunk sizes
would only reduce the likelihood of the timeout; the nonblocking FS broker
eliminates disk I/O from the SPI7 ACK thread altogether.

Backward paging uses new `M2_SEEK ($2B)`: send `M2_ARM ($21)`, write
the two-byte little-endian entry offset via `$C0B5`, and issue `$2B`.
It changes only the in-memory catalog cursor, not the SD/FatFS directory
handle or HxCMOD playlist. The Apple ProDOS picker computes
`offset = page_number * 12` with 16-bit arithmetic and fetches the
next 12 records. Both the BL616 Stage 2 and updated `A2MEDIA.SYSTEM`
are required for this async/seek feature. The slot-6 Floppy Emu is
unaffected.


### Console folder-list latency and timings

The MCU console's `disk_list_begin` enumerates **only the currently
selected FAT directory**: one `f_opendir`, one `f_readdir` stream through
that folder's entries, and one in-memory qsort. It does **not** recursively
walk each subfolder, unless the user explicitly requests **JUKEBOX: WITH
SUBFOLDERS** (which uses the separate jukebox scanner). The console's
Previous/Next 48-entry pages copy from its in-RAM catalog. Entering a
different folder or navigating up performs another scan.

A `/ProTracker` folder containing just 39 subdirectories should require far
less directory work than a leaf folder with ~506 MODs. SD I/O can still be
slow because the current `sdmm.c` implementation transfers each data byte
through three BL616-to-FPGA SPI register operations (write XFER, poll
STATUS, read XFER). A 512-byte sector therefore involves at least 1,536
register operations, excluding command setup and waits. FatFS long
filenames may occupy multiple 32-byte directory entries each.

To distinguish transport cost from unexpected enumeration, the MCU now
prints an additional diagnostic after each console folder scan:

```
PICK DIR: 0:/ProTracker raw=39 dirs=39 mods=0 other=0 prefix=0 long=0 rc=0
PICK TIMING: /0:/ProTracker
  OPEN=... READ=... SORT=... ms
```

Compare `OPEN`, `READ`, and `SORT` when navigating into a 506-file folder.
The measured values and raw entry count identify the actual bottleneck
without guessing. This diagnostic does not affect the FPGA bitstream,
Floppy Emu, or MOD audio path.

### Apple IIgs J command and MCU-wide freeze: double catalog memory

Hardware report after both IIe and ROM 3 IIgs folder traversal work:
**J** (jukebox start at the highlighted file) in `ProTracker/1` with
~506 entries may apparently halt the Apple app **and MCU USB keyboard**,
although starting the jukebox from the console works. The MCU
`vApplicationMallocFailedHook()` permanently disables interrupts and
halts when heap allocations fail, a credible explanation (not yet
confirmed without a fault marker). A prolonged SD scan is a second
possibility.

The M2 Apple FAT browser previously kept **one `pvPortMalloc` string per
entry** in a 512-pointer catalog; unlike the MCU console picker, this
catalog stays allocated while `mod_audio_jukebox_start_from_file()`
starts the independent MOD-thread playlist scan and allocates hundreds
of complete filenames. On this M2 branch the Apple catalog is now a **compact,
chunk-allocated name arena**: up to 20 blocks of 2 KiB each and 512
small index records, instead of 506 independent heap allocations.
Normal ProTracker file names use only the blocks actually needed.
Each block uses libc `malloc()` under the FreeRTOS scheduler lock,
matching SDK heap_3 serialization but without `pvPortMalloc()`'s
fatal out-of-memory hook. Low-heap conditions now return an M2 FAT
browse error instead of disabling interrupts; this preserves the
USB keyboard and error reporting. A–Z ordering, `DIR_SEEK`, and
forward/backward page behavior remain unchanged. The MCU console
jukebox and HxCMOD engine remain untouched.

The M2 host integration test now enumerates 506 entries, starts the
selected-file jukebox while the catalog is still active, confirms the
directory remains usable, and asserts **zero per-filename
`pvPortMalloc()` calls**. It additionally tests 506 long filenames
and forces `malloc()` failure, expecting a recoverable M2 error.
Hardware must confirm whether the interrupted keyboard symptom is
resolved. If the MCU still freezes, inspect the existing fatal diagnostic
marker (DebugOverlay): `ED E1 E1 E1 ED` means malloc-failure hook,
`ED E2 <task initials> ED` stack-overflow hook, `EF` is a CPU exception;
absent those, investigate scheduling / SD scan progress. The `$E1`
printed by the Apple app is a separate **mailbox ACK** error code and
does not itself mean FreeRTOS heap exhaustion.
