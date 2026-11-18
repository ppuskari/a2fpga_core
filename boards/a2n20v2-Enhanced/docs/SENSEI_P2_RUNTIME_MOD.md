# SenseiPlay8 P2: generic runtime ProTracker player

> Note: This document describes the earlier Stage A file-loader milestone.
> For the current sample-DMA and playback implementation, see
> [SENSEI_P2_PLAYABLE_CANDIDATE.md](SENSEI_P2_PLAYABLE_CANDIDATE.md).
> Stage B is now implemented and portable-C / FPGA simulation tested,
> but full board synthesis, BL616 SDK linking and physical HDMI playback
> have not yet been verified.


**Status: developer branch, NOT a flashable music-player release.**

Goal: one permanent IIe launcher and BL616 firmware, open any
supported four-channel ProTracker MOD file **at runtime** from a
folder/file picker. No song-specific ProDOS executables, no generated
private song headers, no offline pattern flattening or effect timelines.

## Current Stage A — implemented in this branch

- Existing BL616 MCU UI provides `MOD LIBRARY` from the main menu and
  reuses the working nested folder picker with `.MOD` filtering
- Selection queues a relative path for `sensei_tracker_task`
- Dedicated `FSOP_MOD_OPEN/READ/CLOSE` operations run in the existing
  disk thread, preserving the non-reentrant FatFS invariant and leaving
  FTP's current file handle untouched
- Original MOD bytes load to BL616 RAM, subject to current 64 KiB
  file-size guard (initial compatibility limit, not a format limit)
- Native C parser validates 31-instrument four-channel MOD headers,
  pattern count and sample offsets, and builds the Ensoniq DOC PCM
  sample bank **at load time**
- The real-time C effect engine traverses the original pattern
  order table directly, including Bxx, Dxx and E6x decisions.
- FPGA P1D 1-ms event FIFO still schedules DOC register updates.
- Synthetic C tests exercise parsing, path filtering, broker calls,
  and real-time pattern flow. No user-supplied MOD is committed to Git.

## Critical Stage B — REQUIRED for actual runtime playback

A safe, acknowledged **BL616 -> FPGA -> DOC Sound RAM upload path** is
still missing. It must arbitrate the shared SDRAM/DOC waveform memory
without interfering with Apple bus transactions or Mockingboard. It
also needs instrument-bank capacity reporting, per-byte data/byte-lane
mapping, backpressure and a completion acknowledgment BEFORE the
MCU claims the DOC register owner and starts music.

Stage A deliberately marks the decoded song as `PCM READY`, **not**
`PLAYING`; the player must not launch notes against stale sample RAM.

Then connect the initialized runtime song to `sensei_mod_tick()` and
enable start/stop from the generic player. Real 15k and Waltz files
should pass without being recompiled into the firmware.

## Final user interface

- **Preferred:** a native Apple IIe ProDOS program providing browse,
  song info, playback, stop, pause, next and optional background mode.
  An IIe directory picker needs an actual ProDOS file transfer
  protocol or volume proxy into the MCU—not merely the new MCU menu.
- **Immediate bootstrap:** the already-functional MCU TAB/menu
  browser on the USB/SD FatFS volume, used to validate the player
  before implementing the native IIe picker.

## Alternate rendering backend (later)

The C tracker decoder/effect model should be reusable by **two**
audio sinks:

1. **DOC sink:** translate notes and volume changes to timestamped DOC
   registers, stage PCM to 128 KiB Enhanced DOC Sound RAM.
2. **PCM sink:** BL616 mixes four (or more) software voices with
   fractional-period interpolation, 16-bit stereo accumulation and
   optional filters, then writes a sample FIFO to FPGA HDMI audio.
   Initially aim for 44.1/48 kHz stereo, benchmark worst-case USB,
   SPI, filesystem and DSP contention before promising quality.

Do NOT swap the proven DOC stereo pins to compensate for conventional
ProTracker channel panning; keep mapping in the renderer.

Existing P1B Waltz, P1C and P1D hardware golden branches remain
untouched. No Stage A firmware should be flashed as a finished P2
player.
