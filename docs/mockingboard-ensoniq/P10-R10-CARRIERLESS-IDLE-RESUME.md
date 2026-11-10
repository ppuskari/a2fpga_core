# P10-R10 — production carrierless SSI-263 with qualified idle suspension

**Target:** `a2n20v2-Enhanced`, BL616 USB-host MCU firmware, Stage2 at `0x40000`.  
**Branch:** `petar/ssi263-p10r10-carrierless-idle-resume-20261110`.  
**Parent:** R9B, `e65cf8e3b8990da8a782421c40e3d44c6ed9102c`.  
**FPGA:** unchanged R6 22.05 kHz-capable bitstream.  
**Status:** C99 host model and renderer syntax checked in GitHub Actions; physical BL616 firmware build, Stage2 programming, optical capture, timing and TAB still require hardware qualification.

## Scope: remove experimental audio processing

- **Zero additional attack shaping**: delete the R7 PCM envelope entirely, not even called for 0us.
- **Remove artificial carrier completely from Enhanced digital synthesis**, at C compile time. The original pinned Pico C source remains its reference default for other platforms, but the Enhanced build compiles `ssi263.c` with `SSI263_DIGITAL_NO_CARRIER=1`: no carrier table synthesis, no periodic carrier sample addition, no per-tick carrier increment. No `-200dB` carrier trick or A/B switch.
- Leave native Pico phoneme ROM, glottal excitation, formant filters, fricative/plosive noise, A/R control, power semantics, 22,050Hz PCM, 44,100Hz HDMI, R8 voiced cosine LUT, USB scheduling, 180s console timeout **unchanged**.
- Delete runtime R9B carrier A/B option, R7 attack/quiet/noise-percentage knobs, and R9 amplitude telemetry. Keep existing `B/S/G`, `RATE/OVR/FIFO` and `CPU/SPI/UND` performance diagnostics.
- Retain older release branches/history; the R10 branch also removes obsolete edge-shaping and carrier A/B test files/workflows from the active tree.

## Qualified idle synthesis suspension

`ssi263_digital_idle.h` controls synthesis, not the audio output gate:

1. Require the *actual rendered* `PCM16` samples to be **exactly zero** for a continuous **2500ms** while the Pico model's A/R request is asserted. A/R alone is **not** sufficient: A/R indicates request-ready, not silence.
2. Once qualified, call `ssi263_skip()` for each upcoming 128-sample source-time block instead of expensive per-sample synthesis. Continue writing zero PCM to the FPGA FIFO each block; **do not stop SPI transport or starve the FPGA FIFO**. `ssi263_skip()` advances the virtual clock and resets silent filter history; it does not pretend to preserve sample-exact oscillator phase across arbitrary delays.
3. On **any** Apple SSI register write in the event burst, clear the sleep state *before* `ssi263_write()` is invoked. No lost first phoneme or time-since-last-write mute. If A/R deasserts, force rendering; any nonzero sample resets the 2.5-second guard.
4. Keep the source rate and FIFO target at 22050/1024; leave the FPGA output unchanged. The idle path saves MCU synthesis CPU cycles; **not** SPI transfers or HDMI power.

Startup:
```
P10 SSI263: Pico C hybrid online
P10 SOURCE=22050HZ DIV=2
P10 R10: NATIVE ATTACK, NO CARRIER
P10 R10: IDLE SKIP AFTER 2500MS
P10 R8: FAST VOICED COS LUT512
```

Periodic report (in addition to prior P10 performance lines):
```
P10 R10 SK=<blocks in 10s> WAKE=<cumulative> Q=<0|1>
```

- SK=0 in active speech and the first ~2.5 seconds of digital silence; then ~1720 skipped blocks per 10s in sustained powered idle with A/R high at the API (active-low pin asserted).
- WAKE increments only when a register write arrives while skipping, not for writes while already awake.
- Q=1 means model synthesis is currently suspended, **not** an A/R electrical state.
- CPU should drop in steady idle, while FIFO remains near 1024 and `UND=0`. First report after speech can contain peaks from prior active synthesis.
- If audio contains a real unvoiced segment or release above zero, the skip path does not engage.

## CI evidence (not a real BL616 hardware qualification)

The C99 host test runs **the same Pico SSI C renderer** with no digital carrier in two states: continuous synthesis and skip/resume. It verifies exact-zero/A-R admission, rejects near-zero/nonzero PCM, guards 2.5sec, ensures write-first wake, and renders the first 48 resumed voiced blocks.

Observed host run: 215 model blocks skipped; exact-zero idle; next voiced block active at block 0 in both baseline and resumed paths; resumed speech energy ratio ~0.9952; wake count 1. This compares timing/energy, not bit-identical sample phase.

## Windows PowerShell — one single-line command per paste

**Use a fresh clone; preserve your R9B carrier-quiet Stage2 binary for rollback.**

```powershell
git clone --branch petar/ssi263-p10r10-carrierless-idle-resume-20261110 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p10r10
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10r10\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
```

If PowerShell lost its SDK environment since reboot, first restore the known tool paths in this process:

```powershell
$env:BL_SDK_BASE='C:/AppleIIgsDev_02/bouffalo_sdk'; $env:PATH="C:\AppleIIgsDev_02\bouffalo_sdk\tools\make;C:\AppleIIgsDev_02\bouffalo_sdk\tools\cmake\bin;C:\AppleIIgsDev_02\bouffalo_tools\xuantie\xuantie-gcc-riscv-v2.10.2-windows-x86_64\bin;$env:PATH"
```

Confirm these locations exist first if your SDK installation is different. Then compile:

```powershell
make -j4
```

```powershell
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object Name,Length,LastWriteTime
```

```powershell
Copy-Item .\build\build_out\a2n20_bl616_host_bl616.bin .\R10_no_carrier_idle_skip.bin
```

```powershell
Set-Location ..
```

**Stage2 flash only** (`0x40000`), with the same proven bootloader procedure:

```powershell
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --port COM13 --verify-flash
```

Confirm COM13 still identifies the board. Require readback verification; a successful write alone does not prove the flash contents. **Never flash Stage1 at `0x0`.** Do not update the FPGA image for this test.

## Hardware acceptance, in order

1. Boot and verify *both* R10 banner lines. TAB should respond during speech, same as R8/R9B.
2. Play Mockingboard Demo Disk 1: same speech fidelity as optical-validated R9B carrier-quiet; no new onset clicks. `R7 E`, `R9 RAW/OUT/AR/LOW`, `CARRIER=QUIET` banners should be absent.
3. While speaking, `RATE` close to 22050/s, `FIFO` near 1024, `G=0`, `UND=0`.
4. After speech concludes but power remains on (`CTL=70` in prior R9B), leave for **at least 15 seconds**: `SK` should climb, `Q=1` in sustained idle, and model CPU cost should fall.
5. Start speaking again after at least 15 seconds of silence; the first syllable must be present, with `WAKE` increasing and `Q=0` during speech.
6. Capture the 44.1kHz optical path; verify silence and no revived 2656.25Hz tone after idle, and no click at the first post-sleep phoneme.
7. Soak for repeated speech/quiet cycles and monitor `OVR`, `UND`, `G`, FIFO, audio, and USB HID.

## Rollback

Flash the preserved, successfully tested R9B carrier-quiet **Stage2** binary using the same programmer and verification settings, then cold-reboot. This restores the previously optical-validated 0-attack, carrier-quiet full-time synthesis path; no FPGA change. Do not use `make flash` or Stage1.

## Limitations

- The host PCM test cannot certify BL616 deadlines, actual SSI hardware bus sequencing, HDMI audio, optical noise, or precise waveform identity after skipping filter history.
- Skip is not a hardware sleep and does not reduce SPI traffic. Longer idle CPU sleep, batching, or SPI-off behavior requires a separate FPGA/MCU protocol design and validation.
- The upstream carrier-enabled Pico model remains separately available for historical fidelity work; R10 Enhanced's production build never generates the modeled carrier.
