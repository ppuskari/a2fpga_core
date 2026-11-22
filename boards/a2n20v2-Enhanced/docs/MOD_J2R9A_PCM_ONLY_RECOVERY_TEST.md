# J2R9A: PCM-only bulk SPI, proven bytewise SDRAM

## Hardware failure in J2R9

J2R9 full-bulk Stage2 produced this console error while loading a MOD:

    MOD: FPGA PAT READBACK FAILED

That error occurs at the beginning/end pattern-bank sentinel check, before
sample staging and before HxCMOD playback starts. J2R9 switched both
SDRAM writes and SDRAM reads to continuous 512-byte SPI bursts, so this
failure does not identify which direction caused corruption.

The FPGA XFER protocol retrieves SDRAM data asynchronously through a
54MHz-domain SDRAM read pipeline. At the 20MHz SPI clock, it is possible
that 512-byte uninterrupted reads outrun that pipeline. This is a
hypothesis, not a confirmed physical root cause.

Keep your known-working J2R8 Stage2 binary. Do not modify Stage1,
FPGA flash/bitstream, or saved A3 audio-mode selection.

## Scope of the J2R9A fix

- Both SPACE1 (SDRAM) reads AND writes return to the proven J2R8
  bytewise SPI implementation. Pattern and sample bank addresses stay
  the same.
- Only SPACE6 writes (direct HDMI signed PCM16LE FIFO) use one
  BL616 bulk SPI call per up-to-512-byte payload transaction.
- The SPI mutex, FPGA protocol header, CS framing, 20MHz mode1 clock,
  3us post-burst CS hold, and non-PCM/non-SDRAM operations are preserved.
- 16KiB pattern LRU, eight 8KiB PCM sample caches, PCM scheduler,
  gain/limiter, speech, disk and A3 routing remain unchanged.
- The host uses FPGA_SPI_MOD_BULK_XFER=1 together with
  FPGA_SPI_MOD_BULK_SDRAM=0. The latter must stay zero on hardware.
  Full legacy fallback: FPGA_SPI_MOD_BULK_XFER=0.

After a successful MOD load, the diagnostic console should display:

    MOD SPI=PCM512 SDRAM=BYTE

This line is emitted after the pattern/sample sentinels have passed.
Press Y:VIEW to switch the MCU MOD Player menu to the console.

## Windows one-line PowerShell commands

Clone into an isolated tree, preserving J2R8 for immediate rollback:

~~~powershell
$j2r9a="C:\AppleIIgsDev_02\a2fpga-jukebox-j2r9a"; git clone --single-branch --branch petar/mod-j2r9a-pcm-only-bulk-20261122 https://github.com/ppuskari/a2fpga_core.git $j2r9a; if($LASTEXITCODE -ne 0){throw "J2R9A clone failed"}
~~~

Build MCU Stage2 using the automatic Bouffalo SDK/GCC/Make paths:

~~~powershell
Set-Location $j2r9a; .\J2R9A.ps1 Build
~~~

If native compilation succeeds, place BL616 into UPDATE/BootROM mode
and flash ONLY Stage2 at 0x40000 (typed confirmation is required):

~~~powershell
.\J2R9A.ps1 Flash
~~~

After reconnecting without UPDATE:

~~~powershell
.\J2R9A.ps1 CheckRuntime
~~~

The wrapper checks Git branch, tracked source fingerprint and built
firmware SHA256. It does not silently overwrite Stage1 or FPGA flash.
It distinguishes a reported Stage2 write from an actual byte readback
and avoids treating an early Stage1 PARTIAL USB identification as a
definitive Stage2 failure.

## Physical test order

1. Start a small four-channel MOD: it must pass SDRAM pattern/samples
   staging and the sentinel readback before any playback begins.
2. In the console confirm the J2R9A PCM-only signature and zero
   pattern/sample access faults.
3. Listen for missing PCM samples or glitches. If the PCM burst
   implementation misbehaves, restore J2R8 Stage2 immediately.
4. Try 3EDGES.mod 8-channel, A_clown_in_the_moon 8-channel and cheer.mod
   in that order. Record UDR slope, RMAX, SMAX, DMIS, LOW, MIS,
   ERR, PF/B/E and PH/EV at comparable frame counts.
5. Improvement is NOT established until actual audio is heard correctly
   and UDR stops growing or significantly decreases. With sample
   SDRAM reads now back to bytewise, RMAX may remain high even if the
   PCM upload SMAX improves.

GitHub mock tests cannot reproduce a BL616/FPGA continuous-burst
timing failure. Native BL616 cross-compilation and hardware testing
remain separate validation requirements.
