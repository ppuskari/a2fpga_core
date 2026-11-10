# P10-R9A — Articulation recovery and idle-tone telemetry

**Target:** a2n20v2-Enhanced **BL616 firmware_host Stage2 only**.  
**Parent:** confirmed R8 commit `348972452cbc3e805699c10a41749c242a11b68c`.  
**Branch:** `petar/ssi263-p10r9a-articulation-idle-diagnostics-20261109`.

## Intent

R8 at 22.05 kHz is hardware-proven to improve TAB response and reduce speech synthesis overruns. A native SSI-263 capture suggested sharper initial consonants; a separately amplified optical capture exposed a persistent narrowband tone during speech-enabled idle. The tone's origin is **not yet proven**. Do not add an unvalidated idle mute or noise EQ.

R9A:
- Changes only `SSI263_R7_ATTACK_US` from **2500 to 1000 microseconds**. The 18 ms prequiet, amplitude threshold, R7 idle algorithm and full speech PCM stay unchanged.
- Preserves R8 cosine LUT, 22.05 kHz source / 44.1 kHz HDMI, task priority, 180 s console and existing FPGA image.
- Adds lightweight, **non-invasive** 10-second `R9` telemetry around the PCM shaping stage:
  - `RAW`: peak magnitude of pre-edge-shaping signed PCM16.
  - `OUT`: peak magnitude of post-edge-shaping signed PCM16.
  - `AR`: blocks where the Pico model's `ssi263_request()` was asserted (request **does not equal silence**).
  - `LOW`: count of rendered 128-sample blocks whose **raw** maximum magnitude was <=256 PCM counts; `PK`: maximum peak among those low blocks; `TH=256` is the classification threshold.
  - All R9 values reset every reporting window. They are **not** a tone-frequency detector; optical FFT remains necessary.
- Identifies startup with `P10 R9A: ATTACK 1MS PCM DIAG`.

## Hardware qualification

1. Preserve the prior known-good R8 **Stage2 .bin** and leave FPGA unchanged.
2. Cross-build under your installed Bouffalo BL616 SDK. Host CI tests syntax and retained settings, not real hardware.
3. Stage2 flash ONLY at `0x40000` with `--verify-flash`; never touch Stage1 at `0x0`. If verify fails or its temporary readback is missing, treat the binary as unverified.
4. Cold reboot, confirm `P10 R9A: ATTACK 1MS PCM DIAG` and `P10 SOURCE=22050HZ DIV=2`.
5. Play identical Demo Disk 1 speech; capture optical audio with matched DAW gain; compare clarity and clicks against R8. Verify TAB works *during* words.
6. Record `CPU`, `SPI`, `RATE`, `OVR`, `FIFO`, `UND`, `G`, `R9 RAW/OUT/AR/LOW/PK`; note that telemetry adds some processing overhead.
7. Capture speech powered but quiet and truly powered off; compare their spectral peaks around the previously observed ~2.656 kHz line. Telemetry cannot by itself distinguish DSP tone from FPGA mixer tone.
8. Confirm console stays ~180 seconds when manually opened; success-mount initial splash is still ~1.5 seconds.

## Windows PowerShell — single-line commands, one at a time

Use an **unused** directory, leaving R8 unmodified:

```powershell
git clone --branch petar/ssi263-p10r9a-articulation-idle-diagnostics-20261109 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p10r9a
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10r9a\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
```

```powershell
make -j4
```

```powershell
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin
```

```powershell
Set-Location ..
```

```powershell
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

The programmer may require your known COM13 selection/bootloader-entry sequence from R8. Check `py -3 .\tools\a2n20-mcu-program --help` before modifying any flags; do not invent `--port` behavior. Flashing to Stage2 is the only intended operation.

## Rollback

Keep the identical R6 FPGA running. Reflash the saved, known-good R8 **Stage2** binary using the same programmer, same Stage2 setting and verification; cold reboot and verify R8 startup logs. Do not flash Stage1.

## Interpretation

- `LOW` with `PK>0` in powered idle is evidence of nonzero raw model output in low-amplitude blocks, *not* proof that those samples generate the 2.656 kHz tone. `RAW` and `OUT` are maxima over a ten-second window, so speech peaks can hide quiet intervals.
- `AR` is model-request activity, **not** a license to mute.
- A harder onset can improve consonants while reintroducing clicks. If so, restore `SSI263_R7_ATTACK_US 2500u` before experimenting with any other audio behavior.
