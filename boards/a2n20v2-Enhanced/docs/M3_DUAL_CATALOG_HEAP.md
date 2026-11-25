# M3 dual-catalog heap optimization (experimental MCU Stage2)

Branch: petar/m3-catalog-heap-compact-20261125
Parent: petar/m3-advanced-console-80col-20261124 (hardware display verified)
Hardware-validated stable release: m3-2026.11.24 (unchanged)

## Reproduced problem

With the M2 Apple ProDOS folder browser open, starting a 500 MOD
jukebox can fail at track 494 with "MCU JUKE: LOW HEAP FOR TRACK ...".
The M2 browser and the jukebox intentionally own **independent**
catalogs, to preserve directory navigation during background playback.

Previously, the jukebox copied each **full** relative file path into
2,048-byte chunks, redundantly storing the common directory prefix 500
times. The M2 browser already stored basenames only, but its 2,048-byte
allocation unit made it vulnerable to low-heap fragmentation.

## Design changes

**Host jukebox (mcu_mod_jukebox.c)**

- Intern each relative directory path once in a per-scan directory table.
- Store compact 4-byte track records (chunk, offset, directory index),
  with only the BASENAME stored in packed filename chunks.
- Reconstruct the identical full path for every start-at-file lookup,
  global case-insensitive sort and playlist playback. Only the MOD PCM
  thread calls mod_jukebox_track(); its returned static scratch string
  is transient and start_song() copies it immediately.
- Use 1,024-byte chunks, retrying 512/256 bytes on fragmented heap.
  256 slots cover 512 maximum-length basenames even at 256-byte capacity;
  normal 500-file scans use only several allocation calls.
- Keep the original 512-track ceiling and original recursion semantics.
  A recursive scan retains its relevant directory strings for playback.
- On errors, return cleanly instead of triggering FreeRTOS' fatal heap
  failure hook. Diagnostics now separate low heap from chunk slot limit.

**M2 A2MEDIA browser (media_mailbox.c)**

- Preserve independent 512-entry global alphabetical catalog and
  nonblocking asynchronous directory scan.
- Allocate basename storage in 1,024-byte blocks, falling back to
  512-byte and 256-byte blocks without calling fatal pvPortMalloc.
- 136 chunk slots cover 512 legal 63-character names even with the
  smallest 256-byte chunks.
- Log name bytes used, actual bytes allocated, chunk count and
  fallback count, with explicit low-heap failure diagnostics.
- Cancellation, seek, page browsing and start-at-selected-file
  continue to work without invalidating the host catalog.

No FPGA, HDL, Apple disk image, source SSI263 voice ROM, or
SynthLAB piano bank changes. The existing M3 FPGA stays in place.
The verified M2 .po also stays unchanged.

## Tests

.github/workflows/m3-catalog-heap-compact.yml exercises:

1. Root and recursive jukebox sorting, exact start-file lookup, 500
   MODs with 62-character names and retrieval of index 494.
2. Jukebox allocation ceilings of 512 and 256 bytes with successful
   500-file scans; no fatal FreeRTOS heap hook.
3. M2 506-name catalog, asynchronous single-pass scan, O(1) backward
   seeking, 62-character names, and 256-byte allocator ceiling.
4. Independent browser/J control under a resident M2 catalog,
   recoverable allocator exhaustion, and cancellation.
5. Prior HDMI 80-column byte-order and 40-column menu regressions.

A successful portable host CI run is NOT a Bouffalo SDK cross-build or
real hardware memory validation.

## Windows 11 PowerShell 5.1 — isolated test worktree

Keep the M3 release files and the working console80 tree intact.
Git fetch needs a full destination refspec in this repository:

    git -C "C:\AppleIIgsDev_02\a2fpga-m3-console80-lab" fetch origin "refs/heads/petar/m3-catalog-heap-compact-20261125:refs/remotes/origin/petar/m3-catalog-heap-compact-20261125"

Do not use --track with this checkout's restricted remote branch
configuration; specify the complete remote-tracking ref:

    git -C "C:\AppleIIgsDev_02\a2fpga-m3-console80-lab" worktree add --no-track -b petar/m3-catalog-heap-compact-20261125 "C:\AppleIIgsDev_02\a2fpga-m3-heap-lab" "refs/remotes/origin/petar/m3-catalog-heap-compact-20261125"

Build only BL616 MCU Stage2. M3.ps1 now checks binary strings for
the new compact-catalog log markers, rejecting stale build outputs:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\AppleIIgsDev_02\a2fpga-m3-heap-lab\M3.ps1" Build

If the build and checksum manifest succeed, Stage2 flash only:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\AppleIIgsDev_02\a2fpga-m3-heap-lab\M3.ps1" Flash

Stage2 programming is restricted to BL616 flash offset **0x40000**.
Never erase or overwrite the signed Stage1 at 0x00000.

## Hardware validation

On the Apple IIe with the original M3 FPGA and existing M2 ProDOS .po:

- Browse a folder with ~500 MODs on the Apple, keep that view open.
- Start a jukebox from the Apple side, then start it again from host MCU.
- Check every track is listed and the last track 500 can be selected.
- Confirm the 80-column TAB console shows JUKE CHUNKS, ALLOC, NAMES,
  DIRS and FALLBACK; M2 CAT CHUNKS, ALLOC, NAMES and FALLBACK.
- Verify UDR stays at 0, ERR stays at 0, and HDMI CLIP remains 00
  while skipping rapidly between MODs and navigating folders.
- Repeat with a folder of longer filenames, where track 494 previously
  failed. Save the allocation summary and any exact OOM line.

Do not promote this experimental Stage2 to the published M3 release
until actual memory usage and playback have passed these checks.
