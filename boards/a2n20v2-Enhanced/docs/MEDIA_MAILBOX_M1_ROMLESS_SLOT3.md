# M1 — ROMless a2fpga Media Mailbox in physical Apple slot 3

Branch: petar/media-mailbox-m1-slot3-console-20261120
Parent: petar/mcupcm-hdmi-direct-mod-clean-20261120

Status: FPGA+MCU sources and portable CI; **not yet synthesized in Gowin,
cross-compiled with BL616 SDK or verified on actual Apple IIe/IIgs hardware.**

## Hardware and scope

- Physical a2fpga in **slot 3** (both Apple IIe and IIgs).
- ROMless device I/O $C0B0–$C0BF. No C300 ROM, C800 ROM, IRQ, or
  slot-4 mouse decodes. No new virtual slot assignment.
- Responds to Apple I/O in both IIe and IIgs modes; not gated by
  virtual slotmaker or native/Enhanced/Shared/Original A3 audio mode.
- FPGA SPI XFER **SPACE7** carries this mailbox, leaving SPACE6
  direct HxCMOD stereo PCM->HDMI, SSI spaces4/5, Uthernet and native
  IIgs GLU/DOC/mockingboard unchanged.
- M1: Apple bytes reach FPGA FIFO and MCU service, **diagnostic
  count/XOR only**. Uploading a complete Apple-local MOD into HxCMOD
  is reserved for M2 after verifying real card bus timing. M1 already
  supports Apple PING, STOP and REPLAY_LAST-selected-MCU-MOD.
- Apple /RESET does not reset the mailbox or background MCU music.

## Apple-visible register ABI (X=$C0B0=49328 decimal)

| Address | Read | Write |
|---|---|---|
| X+0 | 0x4D = 'M' | ignored |
| X+1 | 0x42 = 'B' | ignored |
| X+2 | 0x01 protocol v1 | ignored |
| X+3 | flags b0 MCU_READY, b1 FIFO_FREE, b2 CMD_PENDING, b3 FIFO_OVF, b4 PLAYING, b5 TEST_UPLOAD, b6 CMD_REJECTED | ignored |
| X+4 | last accepted command | write command when none pending |
| X+5 | 0 | push 1 byte to FIFO |
| X+6 / X+7 | FIFO free count LE16 | ignored |
| X+8 / X+9 | FIFO queued count LE16 | expected transfer length LE bytes 0-1 |
| X+A | command sequence | expected transfer length byte 2 |
| X+B | last acknowledged command sequence | expected transfer length byte 3 |
| X+C | last result code | ignored |
| X+D / X+E | FIFO overflow count LE16 | ignored |
| X+F | 0xA5 marker | ignored |

Commands to X+4: 1=PING (returns 0xA5); 2=REPLAY_LAST (0 or
0xE2 if no local MCU-selected MOD); 3=STOP (0); 16=BEGIN_TEST_TRANSFER;
17=END_TEST_TRANSFER (0, 0xE3 no begin, 0xE4 bad length); 18=ABORT (0);
unknown commands return 0xEF.

**Application protocol:** Wait for MCU_READY, ensure CMD_PENDING=0,
write command at X+4; wait for X+B to match the incremented X+A
sequence; check result X+C. Before writing each byte to X+5, check
FIFO_FREE at X+6/X+7. FPGA FIFO holds **256 bytes**; overflows drop the
new byte and increment X+D/X+E. The MCU drains FIFO in 32-byte chunks.
For diagnostic upload set the 32-bit expected length via writes
X+8..X+B, then BEGIN, transfer bytes, wait for queued count 0, END.
Zero expected length means unchecked. M2 will add a complete MOD file
upload protocol with stronger integrity/commit behavior.

## MCU console/keyboard test, without Apple code

Use USB keyboard TAB to open MCU view, Y to switch to the MENU, choose
**MEDIA MAILBOX**, then:
1. **DUMP M1 STATUS TO CONSOLE**: FPGA protocol/ready, number of
   real Apple bus reads/writes, FIFO queued/free, command seq/ack,
   last result, diagnostic count/XOR and overflow count.
2. **RUN MCU/FPGA FIFO LOOPBACK**: when idle, FPGA injection of
   BEGIN, 8 bytes to the identical FIFO, read them over SPI7, END;
   confirms checksum/count and prints M1 SELFTEST PASS 8B XOR=...
3. Press Y to switch back to CONSOLE view and read the logs.

MCU loopback validates the SPI7 command/FIFO and C service but **does
not prove physical Apple bus decode**. Only real Apple PEEK/POKE
increments the Apple read/write hit counters.

Telnet TCP23 console (not menu): lowercase **p** requests probe status;
uppercase **P** runs selftest.

## Apple IIe BASIC physical-bus test

After both FPGA SRAM and MCU Stage2 have the new M1 build, boot BASIC:

~~~basic
PRINT PEEK(49328),PEEK(49329),PEEK(49330)
~~~

Expected **77 66 1**. PING:

~~~basic
POKE 49332,1
PRINT PEEK(49338),PEEK(49339),PEEK(49340)
~~~

Readbacks are command sequence, acknowledged sequence and result.
Allow the MCU its polling interval; the first two must eventually
match, and result should be **165** (0xA5). M1 console status must
show an increased actual Apple read/write count.

Then select a 4-channel FAT .MOD from the existing MCU MOD PLAYER,
and from Apple BASIC enter POKE 49332,3 for STOP or POKE 49332,2
to replay last selected local MOD. None writes native DOC registers.

For 3-byte diagnostic transfer (XOR should equal 0):

~~~basic
POKE 49336,3:POKE 49337,0:POKE 49338,0:POKE 49339,0
POKE 49332,16
REM WAIT FOR SEQUENCE PEEK(49338) = ACK PEEK(49339)
POKE 49333,17:POKE 49333,34:POKE 49333,51
REM WAIT FOR QUEUED COUNT PEEK(49336) = 0
POKE 49332,17
REM WAIT FOR ACK. CHECK PEEK(49340) = 0
~~~

On IIgs, use a test program/monitor capable of explicit C0B0 I/O
access; verify physical slot3 and the IIgs /M2SEL routing separately.
Passing on IIe does not establish IIgs hardware compatibility.

## Windows PowerShell 5.1: copy/paste each line individually

### Isolated checkout

~~~powershell
$hw = 'C:\AppleIIgsDev_02\a2fpga-mailbox-m1'
if (-not (Test-Path "$hw\.git")) { git clone --branch petar/media-mailbox-m1-slot3-console-20261120 --single-branch https://github.com/ppuskari/a2fpga_core.git $hw }
git -C $hw fetch origin petar/media-mailbox-m1-slot3-console-20261120
git -C $hw switch petar/media-mailbox-m1-slot3-console-20261120
git -C $hw pull --ff-only origin petar/media-mailbox-m1-slot3-console-20261120
git -C $hw log -1 --oneline
~~~

### Existing piano/SSI263 assets (do not alter base sound designs)

~~~powershell
Set-Location $hw
py -3 .\tools\extract_synthlab_piano.py --download
py -3 .\tools\extract_synthlab_piano.py --check
py -3 .\tools\generate_ssi263_voice.py
py -3 .\tools\generate_ssi263_voice.py --check
py -3 .\tools\generate_ssi263_p8_roms.py --check
py -3 .\tools\generate_ssi263_p9_nas_rom.py --check
py -3 .\tools\generate_ssi263_p9_output_fir.py --check
~~~

### Gowin GUI ONLY (FPGA SRAM, never golden flash)

Open:
C:\AppleIIgsDev_02\a2fpga-mailbox-m1\boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj

Synthesize, place/route, check timing, and program **volatile SRAM only**.

~~~powershell
Get-Item "$hw\boards\a2n20v2-Enhanced\impl\pnr\a2n20v2_enhanced.fs" | Select-Object FullName,Length,LastWriteTime
~~~

### Build and program BL616 application Stage2 only

~~~powershell
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host"
make -j4 CHIP=bl616 BOARD=bl616dk
if ($LASTEXITCODE -ne 0) { throw 'M1 MCU build failed - do not flash' }
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616"
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
~~~

Never use make flash. Keep the Sipeed signed Stage1 at 0x00000,
Stage2 at 0x40000 and the golden FPGA flash unchanged.

CI is not proof of Gowin place/route, BL616 SDK link, physical Apple
bus timing, ROM mapping or actual audio on hardware.
