# J2R9: targeted bulk512 SPI stress build for cheer.mod

**Hardware target:** Tang Nano 20K a2n20v2-Enhanced / Apple IIe / BL616.
**Only BL616 MCU Stage2 at 0x40000 is programmed.** Signed Sipeed Stage1,
FPGA flash/bitstream, all A3 audio modes, existing Ensoniq DOC and
Mockingboard projects stay unchanged.

## J2R8 baseline: cheer.mod, 8 channels

| Diagnostic | Observed |
| --- | ---: |
| UDR | 437, increasing during dense percussion |
| RMAX | 76,762 us for one 256-frame HxCMOD render |
| SMAX | 20,339 us for a 1024-byte HDMI PCM FIFO upload |
| DMIS | 8 simultaneous 8KiB sample-page misses in one block |
| LOW | 0 FPGA FIFO frames |
| Pattern faults (E) | 0 |
| Sample faults (ERR) | 0 |
| Cache setup | 16KiB patterns + 8 x 8KiB samples |

One PCM block at 44.1kHz is 5.8ms of audio, and the full 2048-frame
FPGA FIFO holds 46.4ms. Existing diagnostics implicate serious latency
but cannot distinguish SPI driver overhead, bus-lock contention,
preemption, or other rendering cost.

## J2R9 architecture

- MCU SPI SPACE1 (SDRAM) reads/writes and SPACE6 (direct HDMI PCM) writes
  use a single bflb_spi_poll_exchange call per XFER transaction chunk
  (7-byte header + up to 512-byte write payload; read uses a 7-byte
  header + mandatory 1-byte dummy + up to 512-byte receive payload).
- The existing SPI mutex is held, and CS# stays asserted through each
  chunk, followed by a 3us hold before CS# deassert to protect FPGA CDC.
- Register accesses and every other XFER space (including W5100, disk,
  overlays, media mailbox and SSI speech) remain bytewise as in J2R8.
- FPGA protocol, 20MHz Mode1 clock, 16KiB pattern LRU, 8 x 8KiB samples,
  postmix gain, 44.1kHz clock and scheduler are unchanged.
- Host build default compile-time option: FPGA_SPI_MOD_BULK_XFER=1.
  To build the legacy-control variant, configure that option to 0
  in a separate test checkout and rebuild. Device firmware defaults to 0.
- The on-screen signature after starting a MOD is MOD SPI=BULK512.
  Legacy-control firmware would show MOD SPI=BYTEWISE.

## Windows PowerShell: one-line commands

Clone into a separate directory, retaining J2R8 as the physical rollback:

~~~powershell
$j2r9="C:\AppleIIgsDev_02\a2fpga-jukebox-j2r9"; git clone --single-branch --branch petar/mod-j2r9-bulk-spi-cheer-20261121 https://github.com/ppuskari/a2fpga_core.git $j2r9; if($LASTEXITCODE -ne 0){throw "J2R9 clone failed"}
~~~

Build the MCU. J2R9.ps1 discovers SDK/GCC/Make/CMake under the
AppleIIgsDev_02 folder. It records both the SHA256 binary digest
and exact tracked source changes in a Build manifest. Because the Git
repository **tracks the output** `firmware_host/build/build_out/
a2n20_bl616_host_bl616.bin`, a successful native rebuild changes that
tracked binary. J2R9 excludes only that generated .bin from its **source**
diff fingerprint, while validating the binary separately with SHA256
both after Build and immediately before Flash. No source edits are
reset or discarded.

~~~powershell
Set-Location $j2r9; .\J2R9.ps1 Build
~~~

After the native SDK build succeeds and you enter UPDATE/BootROM mode,
write the image **only at MCU address 0x40000**. Typed confirmation is
required. Do not run the programmer's default auto-detection/auto-flash
operation, which can select Stage1.

~~~powershell
.\J2R9.ps1 Flash
~~~

After power-cycling without UPDATE, give Stage1 time to chain-load the MCU
application; then optionally check the USB identity:

~~~powershell
.\J2R9.ps1 CheckRuntime
~~~

Verify MOD playback OSD displays:

~~~text
MOD MCU CACHE=16384B
MOD SMP CACHE=8x8192B
MOD SPI=BULK512
~~~

The flash script reports flash WRITE success without asserting a
byte-for-byte BootROM readback. The optional VerifyReadback action is
separate and may fail due to Bouffalo readback-tool limitations.
A transient Stage1-only PARTIAL USB result does not establish failure.
If a local tracked source file is modified, the script reports it and
fingerprints those changes instead of deleting or silently ignoring them.

## Hardware regression order

1. Known-good 4CH MOD: no audio distortion, no sustained UDR growth.
2. 3EDGES.mod 8CH: FPGA pattern bank still reads correctly, E=0.
3. A_clown_in_the_moon 8CH: compare dense drum-run sections with J2R8.
4. cheer.mod 8CH: the primary stress case. Record UDR slope, MIS, ERR,
   RMAX, SMAX, DMIS, LOW, PF/B/E, PH/EV at similar frame counts.
5. Listen for actual interruptions. The goal is to reduce UDR growth
   and bring render + upload latency consistently within FIFO headroom.

If the MCU fails to boot, sample staging fails, or sound is corrupted,
restore the saved working J2R8 MCU **Stage2 only**. Never change Stage1,
FPGA bitstream, or the persistent A3 audio personality in this trial.

## Verification scope

GitHub CI compiles the *actual shared SPI source* against a simulated
BL616 and verifies byte-exact XFER framing, chunk boundaries, mandatory
read dummy, and preserved non-MOD paths in both bulk and legacy mode.

Host tests cannot establish the actual BL616 SPI peripheral's continuous
burst behavior or timing of the real FPGA CDC/SDRAM read path. Native
Bouffalo SDK compilation and physical audio playback remain separate
validation gates.
