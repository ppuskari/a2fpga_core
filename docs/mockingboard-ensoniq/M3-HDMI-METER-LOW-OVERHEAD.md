# M3 experiment: low-overhead HDMI peak/clip reporting

**Branch:** `petar/m3-mb-timing-prodos-suite-20261123`.  
**Unchanged known-good production branch:** `petar/m3-sd-sector-burst-20261123`.

## Design and resource budget

The existing FPGA HDMI mixer remains completely unchanged. The new read-only
`hdmi_mix_meter.sv` observes FINAL signed 16-bit HDMI samples (after native
AY/DOC/SSI gain, MCU MOD at unity, and -2 dBFS combined hard guard).

* FPGA pixel-clock domain: two 16-bit absolute-value comparators and
  one-second maximum registers; resettable 16-bit count of the 44.1kHz
  sample-enable pulses. One snapshot per 44100 frames.
* Clock crossing: one toggle synchronizer, and a single 40-bit sample/clip
  bundle that is held stable for ~1 second; logic-clock data is captured after
  the synchronized toggle has settled. No audio stream crosses back.
* No new FPGA multipliers, DSP blocks, SRAM, SDRAM, NCO, codec filters,
  render tasks, IRQs or sample-rate scheduling changes.
* SPI: extend existing XFER SPACE6, **read 9 bytes at 0x800010**; old
  16-byte `PC v1` status at 0x800000 and its FIFO/reset/write ABI unchanged.
  The status read is atomic across the 9-byte packet (latched on byte 0).
* MCU: sample optional meter once per 1000ms while a MOD is playing, only
  when no urgent FIFO refill is due. Eight-to-nine readouts are combined
  into the existing ~8.9-second performance report. Peak-to-dBFS
  conversion uses integer-only 8-iteration log2 at report time.
* Traffic: 9 diagnostic payload bytes/s (+ one standard XFER header and
  dummy). Compared with 44,100 frames/s * 4 bytes = 176,400 PCM B/s,
  the telemetry **payload** is 0.0051% of PCM payload throughput.
  The separate transaction/mutex overhead is not included in that ratio.
* CPU cost is a single short SPI read per second plus two dB conversions
  per existing 8.9s status batch. No extra operations inside HxCMOD render.

Actual LUT/FF usage, timing slack and elapsed SPI lock duration must be
measured by Gowin and physical MCU telemetry. An isolated Yosys synthesis
step is included as a coarse standalone resource estimate; do not claim
a Gowin P&R result until compiled locally.

## SPACE6 meter read ABI

All values are from a 1-second snapshot, stable and coherent in logic clock:

| Byte at 0x800010+ | Meaning |
|:--|:--|
| 0 | 'H' (0x48) capability magic |
| 1 | 'M' (0x4D) |
| 2 | 0x01, protocol version |
| 3 | 8-bit HDMI over-peak history (one bit per ~125ms bin, bit0 newest) |
| 4 | left unsigned 16-bit sample peak, low byte |
| 5 | left peak, high byte |
| 6 | right peak, low byte |
| 7 | right peak, high byte |
| 8 | bit0=one-second snapshot valid |

If an older FPGA is running, the MCU recognizes a missing 'HM1'
signature and skips all HDMI reporting silently. The first snapshot
is valid after approximately one second. All other fields are read-only.

A signed PCM value of -32768 yields unsigned magnitude 32768, not -32768.

## Console line

Example *format*, not a claimed physical measurement:

```text
HDMI CLIP=00 L=-2.3 R=-2.8
```

Here L/R are the largest **sample peaks** seen by the MCU's 1Hz
polling over the current ~8.9s report, formatted as dBFS. They are not
LUFS, RMS, dBm or intersample true peak. Value 26028 maps to -2.0dBFS.

CLIP is the bitwise OR of successive one-second history snapshots over
the report window, **not** a live 125ms-by-125ms timeline for the full
8.9-second report. 00 means no over-peak history was observed by those
polls. Any nonzero value shows limiting occurred; FF does *not* prove
continuous clipping across all 8.9 seconds. Cross-check with SpectrumWall.

With a silent channel, the line prints raw unsigned sample peaks:

```text
HDMI CLIP=00 PK=0/26028
```

The mixer has a hard -2 dBFS ceiling while MOD is present. A peak
reading of -2.0dBFS with frequent nonzero CLIP history means hard
limiting is active; it is not proof of distortion-free output.

## Build, test and roll back

**Both FPGA and BL616 Stage2 are required to see the new console line.**
Existing audio playback does not require this new Stage2; its sole new
responsibility is reading optional meter data. Stage1 is untouched.

On the separate Windows experiment checkout, after `git pull --ff-only`:

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-m3-hdmi-lab
git pull --ff-only
.\Build-M3-FPGA.ps1 Build -Offline -GowinCli 'C:\Gowin\Gowin_V1.9.10.03\IDE\bin\gw_sh.exe'
```

The helper verifies all SSI263 and SynthLAB assets, archives previous
bitstream/timing artifacts, validates the Gowin Tcl completion marker.
Use previously verified `piano_multisustain.mem` as in the working
experiment, or provide the verified original SynthLAB source `.po`.

**Load the FPGA .fs into volatile SRAM only.** Do not overwrite FPGA
configuration flash until the lab build passes.

```powershell
.\M3.ps1 Build
.\M3.ps1 Flash
.\M3.ps1 CheckRuntime
```

The experimental M3 helper allows only the golden and explicitly named
experiment branches, and binds the Stage2 binary SHA256 and source
fingerprint to the exact branch/commit for its Flash step. Existing
Stage1, startup flash config and audio mode preferences remain untouched.
The Flash operation requires the helper's interactive confirmation.

Regression scripts are in `.github/workflows/m3-mod-hdmi-unity.yml`:

* HDL mixer samples never change; existing full -2 dBFS peak guard stays.
* HDL one-second L/R peak, clip and bundled-data CDC, including -32768.
* PCM SPACE6 legacy first 16 status bytes and atomic 9-byte extension.
* Pure integer dBFS conversion within 0.11 dB of the logarithmic reference.
* Isolated Yosys synthesis resource report for the small meter.

If the experiment misbehaves, reload the golden M3 FPGA into volatile
SRAM and restore golden M3 Stage2 using its guarded build/flash helper.
No asset, SD burst or existing audio decoder changes are involved.
