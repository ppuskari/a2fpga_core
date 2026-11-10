# P10-R9B: zero-attack PCM and carrier-source A/B diagnostic

**Board:** a2n20v2-Enhanced, BL616 `firmware_host` **Stage2 only**.  
**Source:** `petar/ssi263-p10r9b-zeroattack-carrier-ab-20261110`, based on R9A commit `090ec5f38f86eed079267e36be29631efdfd1bc5`.  
**FPGA:** unchanged R6 22.05kHz-capable bitstream. **MCU:** R8 512-point cosine LUT, USB PSC/HID scheduling, 180-second console unchanged.

## Findings from actual C source and optical recordings

The `R9 RAW=10 OUT=10` number from R9A is a **peak PCM16 amplitude (10 counts)**, **not 10 packets**. `R9 LOW=1722` counts 128-sample blocks. At 22.05kHz, ~1723 blocks is ~10 seconds.

The pinned Pico model constructs a deliberate modeled carrier in `reference/ssi263/pico-v1.0.1/ssi263.c`:

```c
real c8 = 0.1 * pow(10.0, p->carrier_rel_db / 20.0);
real c4 = c8 * pow(10.0, p->carrier_h2_db / 20.0);
c->carrier[i] = c8 * sin(2 * M_PI * i / 8.0) +
                c4 * sin(2 * M_PI * i / 4.0);
...
if (pw || carrier_off)
    v += c->carrier[c->tick & 7];
```

Default `carrier_rel_db=-60`, `carrier_h2_db=-10`; the firmware uses `params.output_gain` in `ssi_pcm16`, which scales output to 32767. This is a strong numerical candidate for the observed ~10-count residual while powered. A/R is *active-low*; `ssi263_request(chip)==1` means the A/R pin is asserted/low (timer/request ready), **not that audio is supposed to be zero**.

The optical idle tone in R9A was measured at approximately 2656.25Hz. The model adds an eight-tick carrier, so its fundamental frequency is `f = XCK / (16*(256 - R4))`. At `XCK=1020000`, `R4=0xE8` would yield **2656.25Hz**. This **R4 value is a hypothesis** until logged from hardware; do not substitute the filter-clock-only hypothesis `R4=0x40` without evidence. R9B prints CTL/R4/mode every ten seconds to confirm.

Whether the real SSI-263 analog chip has comparable carrier leakage is **not proven**; a silent DAC is an expectation that needs analog control measurements. Suppressing the modeled carrier may improve SNR but could diverge from the chip's authentic behavior. This build changes no FPGA gates or AY/DOC mixing.

## R9B primary behavior: ZERO attack shaping

`SSI263_R7_ATTACK_US=0u`; no call to `ssi263_audio_edges_sample()` is compiled into the main PCM loop, and `R7 E=0` is retained only for comparison. PCM samples are sent unchanged through the existing SSI transport. No 1ms or 2.5ms attack smoothing; native Pico phoneme transitions remain.

## Carrier A/B switch

R9B defaults to the **original** Pico carrier (`SSI263_R9B_CARRIER_QUIET_TEST=0u`), giving a clean *zero-attack-only* comparison to R9A.

For a **separate** second build, change `SSI263_R9B_CARRIER_QUIET_TEST` to `1u`. In that mode only, before model creation, `params.carrier_rel_db=-200.0f`: the default modeled carrier is negligible after PCM16 quantization; no changes to the reference C source, noise generator, voiced DSP, or speech register/A/R handling. Startup logs `P10 R9B CARRIER=QUIET` instead of `...ORIGINAL`. This is an intentionally *diagnostic* mode, not an authenticated emulation fix.

A/B acceptance: record powered idle vs power-off optical spectrum and confirm whether ~2656Hz drops; compare the same Demo Disk 1 speech for fidelity and clicks. Do not change volume, FPGA, or capture gain between takes. Existing `R9 RAW/OUT/AR/LOW/PK`, `RATE/OVR/CPU/SPI/UND/G` remain. Added `R9 CTL=.. R4=.. MODE=..` shows model state; observe that `R4=E8` if the exact 2656.25Hz carrier formula holds.

## Windows PowerShell: one command per paste

Clone into a new directory and keep your known-good R9A/R8 image:

```powershell
git clone --branch petar/ssi263-p10r9b-zeroattack-carrier-ab-20261110 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p10r9b
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10r9b\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
```

```powershell
make -j4
```

```powershell
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin
```

```powershell
Copy-Item .\build\build_out\a2n20_bl616_host_bl616.bin .\R9B_attack0_carrier_original.bin
```

```powershell
Set-Location ..
```

```powershell
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --port COM13 --verify-flash
```

Check that COM13 is still the BL616 bootloader port, enter board bootloader mode as in R9A, and insist on readback equality, NOT just a reported Stage2 write. **Never flash Stage1 at 0x0.** Verify `P10 R9B: ATTACK BYPASSED`, `P10 R9B CARRIER=ORIGINAL`, and `P10 SOURCE=22050HZ DIV=2` on reboot.

For **optional separate carrier-quiet A/B** from inside `firmware_host`, first return there:

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10r9b\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
```

```powershell
$p='.\ssi263_hybrid.c'; $s=[IO.File]::ReadAllText($p); [IO.File]::WriteAllText($p,$s.Replace('#define SSI263_R9B_CARRIER_QUIET_TEST 0u','#define SSI263_R9B_CARRIER_QUIET_TEST 1u'),(New-Object System.Text.UTF8Encoding($false)))
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
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --port COM13 --verify-flash
```

Verify boot log `P10 R9B CARRIER=QUIET`. For rollback, flash the saved R9A .bin or `R9B_attack0_carrier_original.bin` with the same `--stage2` settings and cold reboot. Do not use a Stage1 operation.

## Success/failure decision

- R9B original (0us attack): compare articulation and powerup/shutdown clicks to R9A (1ms), with unchanged idle tone expected.
- R9B carrier-quiet: if raw idle PCM drops to zero, optical tone drops, and speech is otherwise equal, the modeled carrier is isolated as the likely residual source. If the 2656Hz optical tone persists with PCM exact zero, investigate FPGA mixing/clocking and other audio sources.
- The R7 idle fastpath may engage only after **2.5s exact-zero output plus A/R request**, as before. If it does, compare immediate post-idle phoneme onset and ISR/USB responsiveness; a new behavior is *not automatically* qualified.
- Do not claim hardware readiness until real BL616 SDK build, Stage2 verification, and optical comparisons succeed.
