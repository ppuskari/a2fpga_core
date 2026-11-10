# P10-R8 — Voiced-Pico DSP acceleration and 180-second MCU console

**Board:** `boards/a2n20v2-Enhanced` only. **Branch:**
`petar/ssi263-p10r8-voiced-dsp-speed-20261109`.

## Real R7A hardware observations

- The R7A model and 22.05kHz FPGA rate negotiation are confirmed operational.
- During powered speech, the R7A screenshots show 22k sustained in some
  windows but **8.8–9.7ms peak model rendering**, above the 5.805ms
  budget for 128 samples at 22.05kHz.
- SPI processing stays near ~0.8–1.1ms in these stressed windows.
- `G=0` while `OVR` often hundreds/10sec and `UND` intermittently
  nonzero; `E` increments, so the R7 attack smoother is active.
- `IDLE=0 Q=0` shows that the **strict** zero-sample/A-R
  quiescence criterion has not been met. Do not aggressively force
  idle skip on sustained phonemes.
- User reports TAB takes effect only in quiet gaps during heavy
  speech: this is a real UI responsiveness regression.

## UI: 180-second timeout and USB scheduling

- `menu.c`: `MCU_SCREEN_TIMEOUT_US = 180000000u`, protecting both
  menu and console views from returning to Apple after only 15 seconds.
- `disk.c`: on mount failure and any early return, the boot/diagnostic
  console now stays on-screen for up to **180 seconds**. **Successful**
  mount still releases its initial boot splash after **1.5 seconds**,
  allowing Apple II video to appear promptly. All paths remain
  nonblocking, so virtual-disk service is not delayed.
- `main.c`: actual board priority
  `CONFIG_USBHOST_PSC_PRIO=28`. The speech service had inadvertently
  been created at the **same priority 28** as the USB host
  port/status-change task (PSC); in a heavy phoneme loop the USB
  host can be delayed. R8 moves speech to **PSC-1 = 27**, below USB
  PSC (28) and HID/menu/XInput poll (29). This fix has not yet
  been qualified on hardware and can change how often audio
  deadlines are missed; always check `OVR/UND`.
- Native `usbh_hidinput` keyboard and consumer-control code,
  USB hub 8-port / 1024-byte control descriptor configuration,
  IIgs video and slot/reset startup are unchanged.

**Important:** This is a *candidate fix*, not yet proof of the
root cause. If TAB still responds only during a quiet phoneme,
inspect USB HID report delivery, shared SPI mutex contention,
and the menu loop's health. Do not regress Enhanced host limits.

## Speech: numerical acceleration

The pinned Pico `ssi263.c` calls `cos(2*pi*phase)` inside the
voiced-noise modulation loop. On BL616, libm calls under heavy
voiced phonemes are expensive. The experimental
`SSI263_R8_FAST_SWELL` option computes 512 cosine values
at model startup and replaces per-tick cosine with linear
interpolation. Approximate lookup interpolation error
is < 1.89e-5 in `cos` magnitude. The offline parity test
renders 49,152 samples at **22.05kHz** through original and
R8 models; the CI checks measured PCM correlation and SNR.

Only the Enhanced BL616 build defines `SSI263_R8_FAST_SWELL=1`
for `ssi263.c` in its `CMakeLists.txt`. Original model behavior
remains the default if that flag is removed or when testing host
reference. The Pico ROM, Ensoniq DOC piano, AY PSG/noise, HDMI
audio rate and FPGA gateware **do not change**.

## Safe Windows PowerShell build

Keep your known-good P10-R6/R7A MCU Stage2 binaries and FPGA
bitstreams unchanged while testing R8.

```powershell
git clone --branch petar/ssi263-p10r8-voiced-dsp-speed-20261109 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p10r8
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10r8\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
```

```powershell
make -j4
```

```powershell
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin
```

After successful **real BL616 SDK** build and saving the
working previous Stage2 file:

```powershell
Set-Location ..
```

```powershell
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

**Never flash Stage1 at `0x0`.** The programmer's previous
readback command may report that the file was not found,
meaning write success alone is not byte-for-byte verification.

Keep the working P10-R6 FPGA with speech at 22.05kHz;
R8 is **MCU-only**.

## Hardware criteria

1. On cold startup with no storage, console auto-hides after ~180s,
   not 15. With mounted disk image, Apple video returns promptly,
   and manually opened menu/console remains ~180s idle.
2. Re-run the *same* Demo Disk 1 speech; repeatedly TAB to switch
   console **during active voiced syllables**, not just pauses.
3. Speech still reports `SOURCE=22050HZ DIV=2`,
   `G=0`, `RATE~22050/S`, no new `UND` in steady conditions.
4. Compare model `CPU` peak, 10-second `OVR` counts and `UND`
   during the same busy phrase against prior R7A. The LUT should
   reduce voiced modulation cost, but not all expensive phonemes
   necessarily use that path.
5. Listen for phoneme fidelity or new noise/glitches.
   With original Pico LUT flag removed and rebuild, can perform
   A/B to isolate numerical optimization.

Host CI is not a substitute for the Bouffalo SDK cross-build or
real Enhanced IIe/IIgs hardware validation.
