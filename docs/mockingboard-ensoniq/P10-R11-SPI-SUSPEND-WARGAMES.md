# P10-R11 — FPGA PCM suspend/resume + BL616 idle SPI saving

**Status:** GitHub host syntax, legacy HDL, new R11 HDL and C model tests PASS. **NOT YET BUILT WITH GOWIN NOR TESTED ON PHYSICAL APPLE IIe**.  
**Parent:** hardware/optical-proven R10 `1b7869230817003ab6cf60c1e03df587f9854803`.  
**Branch:** `petar/ssi263-p10r11-spi-suspend-wargames-20261111`.  
**Board:** a2n20v2-Enhanced Tang Nano 20K / BL616; slot 4 Mockingboard; SSI263 at 22.05 kHz, HDMI audio at 44.1 kHz.

## What changes and why

R10 does ~172 PCM16 SPI writes of 256 bytes/sec even during sustained digital silence. Its source-level model skip already reduced CPU time for each 128-sample idle block from about 2500us to 40-45us, but the SPI driver still spends ~320us per block transferring zeros. R11 makes this remaining cost optional, *without stopping event reads*.

New FPGA XFER SPACE4 control `0x800002`:
- `0x01` => suspend PCM stream; atomically clear queued PCM and playing state, output digital zero; **do not increment UND** during intentional pause
- `0x00` => resume PCM stream; clear stale PCM and playing state; require the existing **512-sample startup watermark** before playing again
- extended SPACE4 status read bytes `26=0xB7` (R11 capability) and `27 bit0` (pause ACK)
- All Apple bus SSI writes, A/R/CA1, XCK and FPGA event queue remain **active in both states**. No gating of events or DOC/AY channels
- pause/resume **preserves** existing UND/OVR counters; powerdown and explicit ring reset keep their normal reset semantics
- new FPGA powers up in unsuspended, legacy behavior; old R10 MCU works on it without changes

R11 BL616 firmware:
- reads 28-byte extended status, requires `0xB7` before enabling SPI suspension
- if R6/R10 FPGA does not expose the capability, **falls back to validated R10 continuous-zero behavior**; there is no dependence on the new register
- requires 2500ms of **exact-zero PCM16 + asserted Pico A/R** before signaling FPGA suspension. A/R alone never means silence
- while suspended, stops 256-byte speech PCM block writes but **still polls FPGA status/events** to catch new SSI writes
- on any Apple SSI write, requests FPGA RESUME and waits for readback ACK **before** popping/applying any SSI event; failed ACK leaves the Apple event unread for retry
- advances the software model's virtual time once after a long pause using `ssi263_skip()`, then applies SSI writes and resumes normal rendering
- FIFO restarts at the existing 512-sample watermark, which at 22.05 kHz represents ~23.2ms of source audio; this affects first-phoneme latency and is a deliberate audio qualification target
- logs `P10 R11 PA=<cumulative> RE=<cumulative> ERR=<cumulative>`, plus R10 SK/WAKE/Q and existing RATE/OVR/FIFO/CPU/SPI/UND

## Qualification done in CI

- Existing P10 bridge and R6 multirate HDMI/FPGA tests pass unchanged
- R11 HDL simulation passes: suspended FIFO flush, zero HDMI speech PCM, no intentional underrun, SSI CPU-write event preserved, acknowledged resume and first PCM sample played after watermark
- Real Pico R10 exact-zero-idle / skip / first-phoneme wake regression still passes
- MCU source compiles in host syntax check for 22.05 and 11.025kHz
- C99 phoneme preview and Apple II 6502 program for `Shall we play a game?` assemble and render; separate instructions in `examples/ssi263_wargames/README.md`

**Limits:** GitHub Actions does not run Gowin placement/routing, actual BL616 firmware build or physical audio. SPI savings and first-phoneme quality remain predictions until tested on real hardware.

## Windows PowerShell deployment: single-line commands

**Save** a known-good copy of the previous R10 MCU Stage2 binary and the known-good R6 FPGA bitstream, separately. Do NOT overwrite them in a new build tree.

Clone the R11 branch into a **new** directory:

```powershell
git clone --branch petar/ssi263-p10r11-spi-suspend-wargames-20261111 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11
```

**FPGA — Gowin GUI:** Open `C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11\boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj` in your existing Gowin EDA installation. Run Synthesis -> Place & Route -> Generate Bitstream. Check full resource/timing reports for timing errors before flashing. The expected bitstream is:

```powershell
Get-Item C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11\boards\a2n20v2-Enhanced\impl\pnr\a2n20v2_enhanced.fs | Select-Object Name,Length,LastWriteTime
```

If `openFPGALoader` is installed, connect the board's **Debug USB-C/JTAG** interface in its usual FPGA-programming mode and run:

```powershell
openFPGALoader -b tangnano20k -f C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11\boards\a2n20v2-Enhanced\impl\pnr\a2n20v2_enhanced.fs
```

The alternative is the standard Gowin Programmer/FPGA UPDATE interface you already use. Do **not** mistake the FPGA `.bin` for the BL616 Stage2 `.bin`.

**MCU — BL616 SDK:**

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10r11\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
```

Restore the earlier known-good SDK PATH only if a new PowerShell session no longer finds `make`:

```powershell
$env:BL_SDK_BASE='C:/AppleIIgsDev_02/bouffalo_sdk'; $env:PATH="C:\AppleIIgsDev_02\bouffalo_sdk\tools\make;C:\AppleIIgsDev_02\bouffalo_sdk\tools\cmake\bin;C:\AppleIIgsDev_02\bouffalo_tools\xuantie\xuantie-gcc-riscv-v2.10.2-windows-x86_64\bin;$env:PATH"
```

```powershell
make -j4
```

```powershell
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object Name,Length,LastWriteTime
```

```powershell
Copy-Item .\build\build_out\a2n20_bl616_host_bl616.bin .\R11_spi_suspend_stage2.bin
```

```powershell
Set-Location ..
```

Enter BL616 ROM bootloader mode (hold UPDATE while connecting Debug USB-C), confirm the COM port, then **Stage2 at 0x40000 only**:

```powershell
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --port COM13 --verify-flash
```

Do not flash Stage1 at 0x00000. Require a successful verification/readback, not just the message that programming completed. Restart the board with both new images.

**Safe rollout order:** Flashing FPGA first preserves compatibility with the old R10 MCU (pause defaults off). Flashing the R11 MCU against the old FPGA is also safe because `CAP=0` falls back to R10. The real SPI-saving mode runs **only** once both new images are present and the R11 capability ACK succeeds.

## Expected diagnostics

Startup `P10 R11: SPI PCM PAUSE CAP=1` (**CAP=0 means old FPGA/fallback**), plus R10 carrierless/idle and R8 cosine banners.

| Phase | P10 RATE | FIFO | UND | PA | RE | R10 Q |
|---|---|---|---|---|---|---|
| Active speech | about 22,050/s | about 1024 | 0 | stable | stable | 0 |
| 2.5s exact silence accumulating | about 22,050/s | about 1024 | 0 | stable | stable | 0 |
| FPGA PCM intentionally suspended | **0/s** | **0** | **0** | increments once | stable | 1 |
| New SSI write and FIFO re-prime | transitions back to ~22,050/s | climbs from 0, then ~1024 | **0** | stable | increments once | 0 |

`RATE=0, FIFO=0` **with Q=1 and CAP=1 are success**, not an underrun, because the FPGA outputs exact-zero PCM itself.

## Hardware acceptance

1. Run known-good Demo Disk 1; voice must sound as crisp as R10/R9B, including the first consonant.
2. Confirm `CAP=1` and `PA` becomes 1 after at least 2.5s powered digital silence; PCM SPI traffic (RATE) drops to zero.
3. Leave idle for 60 seconds and confirm `UND=0`, `G=0`, `ERR=0`; any new event should still be visible to BL616.
4. Restart speech without resetting the computer; `RE` increments, `Q` drops to 0 and PCM resumes at 22k/s with FIFO filling.
5. Listen and capture optical: compare the **first 300ms** after wake with R10; check for clicks, vowel clipping, silence longer than the existing R10 path, or missing consonants.
6. Cycle through speech, >15s idle, speech **20+ times**, with USB TAB activity and active disk/OSD to expose SPI contention.
7. Observe SPI time and activity; do not confuse R11's zero PCM RATE during suspension with a software synthesizer fault.

## Rollback

Keep both R10 MCU Stage2 and its prior R6 FPGA bitstream. To reverse R11, **flash the known-good R10 MCU Stage2 binary first** (with verification) and then restore the R6 FPGA image. This avoids the R11 MCU unexpectedly trying a new suspend handshake on a legacy FPGA; the MCU also has fallback but the old paired build is the final baseline. Neither operation should touch Stage1.

## Separate demonstration: WarGames-inspired Joshua/WOPR

See `examples/ssi263_wargames/README.md`. This program uses real SSI-263 phoneme codes on slot 4, not copied movie audio. It explicitly sends an SSI power-down at completion, making it a useful R3 power-off behavior test as well.
