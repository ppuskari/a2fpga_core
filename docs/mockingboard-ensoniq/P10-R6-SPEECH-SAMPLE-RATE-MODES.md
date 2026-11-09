# P10-R6 — 22.05/11.025 kHz speech PCM with unchanged 44.1 kHz HDMI

**Board:** `boards/a2n20v2-Enhanced` — not the regular a2n20v2.

## Why

P10-R5 real hardware achieved ~44,100 samples/s steady-state, with
intermittent 36–40k/s periods and 6 ms peak speech render time;
SPI remained mostly ~400–450 us per 256-byte transfer.
22.05kHz cuts the PCM payload and target sample-generation rate
by 2 while preserving the 44.1kHz clock of the whole HDMI output
and original DOC piano and Mockingboard AY effects.

The native SSI263 voice is perceptually band-limited, but the
hybrid stream is actually 16-bit PCM, not automatically "under 8-bit".
**Change sample rate first, not PCM resolution.** 11k is a useful
lower-bandwidth reference but can reduce consonant/fricative quality.

| Source rate | mono PCM16 SPI | Per 128-sample block budget | HDMI output |
|---|---:|---:|---|
| 44,100 Hz | 88,200 bytes/s | 2,902 us | 44,100 |
| **22,050 Hz (default)** | **44,100 bytes/s** | **5,804 us** | 44,100 |
| 11,025 Hz | 22,050 bytes/s | 11,609 us | 44,100 |

The bandwidth figures count the PCM payload, not SPI framing or SSI
register/event traffic. No assumptions about ADC bit depth are made.

## Design

`boards/a2n20v2-Enhanced/hdl/ssi263_hybrid_bridge.sv` remains
a 2,048-sample 16-bit FIFO. It uses the existing **real 44.1kHz
HDMI sample strobe** and a 2-bit phase counter. At 22.05kHz
the FPGA consumes one source sample for every two HDMI audio
periods, holding that 16-bit sample through the intervening
period. At 11.025kHz it consumes one per four. No audio clock
domain or Ensoniq DOC/AY logic changes.

The MCU source rate is **negotiated at startup** (not reconfigured
while speech is playing):

- Existing 24-byte SPI status at space 4 address 0x800000
  stays bit-for-bit backward-compatible. Version remains 1 and
  final bytes remain `P1`.
- Extension bytes 24/25: `0xA6`, mode `0|1|2`.
- Write mode 0|1|2 to space 4 address `0x800001` to select
  **44,100 / 22,050 / 11,025 Hz**; this atomically clears the
  PCM queue, audio-hold phase and underrun/overrun counters.
- Power-down and ring-reset behavior remain unchanged, including
  no stale PCM replay across SSI CTL power transitions.
- An **old P10-R5 MCU** with the R6 FPGA stays at 44.1kHz
  (default mode 0, no configuration write).
- An **R6 MCU** with the old P10-R2 FPGA reads 0x31 instead of
  0xA6 at byte 24 and falls back to 44.1kHz synthesis.
- If R6 MCU sees R6 capabilities but cannot confirm a rate
  write/readback, it retries three times, then returns to
  44.1kHz only after a positive fallback ACK, or refuses
  to start speech rather than mismatching sample rates.

The **only changed production files** are the SSI FPGA FIFO module
and the hybrid MCU renderer. Enhanced Nov 6 HID keyboard+remote,
8-port hub support, 1024-byte USB configuration buffer,
full IIgs video, voice/piano gain and reset/slot-handshake paths
are retained unchanged from hardware-proven P10-R5.

## Select 11.025 kHz later

In `firmware_host/ssi263_hybrid.c` the default is:

```c
#ifndef SSI263_PCM_RATE_DIV
#define SSI263_PCM_RATE_DIV 2u
#endif
```

Set `SSI263_PCM_RATE_DIV` to `4u` for 11.025kHz, or `1u`
to restore 44.1kHz. **Changing the MCU rate does not require
another FPGA build** once R6-capable gateware is installed.
The MCU reads the FPGA mode back before initializing its Pico engine.
Only change the rate between boot sessions.

## One-line PowerShell 5.1 Windows build steps

**Do not use the existing local P10-R5 checkout:** it has its own
single-branch fetch settings and stores the working Gowin outputs.

```powershell
git clone --branch petar/ssi263-p10r6-multirate-speech-20261109 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p10r6
```

For the MCU, run separately:

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10r6\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host
```

```powershell
make -j4
```

```powershell
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin
```

For the FPGA, open this exact project in Gowin Programmer IDE:
`C:\AppleIIgsDev_02\a2fpga-ssi263-p10r6\boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj`.
Run full synthesis/place-route/STA and confirm **0 setup/hold
violations** with the native IIgs VGC intact. The P10-R2 STA
success does not establish the R6 timing result.

**Deployment order:** preserve the known-good R2 `.fs` and
R5 Stage2 `.bin`, then program the **R6 FPGA bitstream first**
(the existing R5 MCU continues to work at legacy 44.1kHz).
Only then, from the fresh checkout's parent BL616 folder:

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p10r6\boards\a2n20v2-Enhanced\src\a2n20_bl616
```

```powershell
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

**Never write Stage 1 or address 0x0.** Previous
`--verify-flash` runs reported successful flash but did not
find the readback file to compare bytes.

## What to expect on hardware

```
P10 SSI263: PICO C HYBRID ONLINE
P10 SOURCE=22050HZ DIV=2
P10 B=... S=... G=...
P10 RATE=22050/S OVR=... FIFO=...
P10 CPU=...US SPI=...US UND=...
```

`RATE` now measures the **source** sample rate: 22,050/s,
not the final HDMI 44,100/s. Target `OVR` is low and `UND`
stable; `G` remains 0; USB TAB and menu must still work.

A 128-sample speech block lasts ~5.805ms at 22k, so a 6ms
occasionally expensive Pico block could still cause isolated
overruns, but the low average CPU workload should let the FIFO
recover more easily. At 11k there is even more headroom, with
possible audible consonant loss.

## Validation scope

GitHub Actions `.github/workflows/ssi263-p10r6-multirate-speech.yml`
performs Icarus bridge simulations for legacy and 22/11 modes,
Verilator lint, host C compile at all configured divisors and
offline Pico-C synthesis at all rates.

**Not yet checked:** physical BL616 SDK rebuild, Gowin hardware
fit/STA, real playback/underflow, bit-perfect I2S capture or
comparative SSI phoneme quality. Keep P10-R5 intact until validated.
