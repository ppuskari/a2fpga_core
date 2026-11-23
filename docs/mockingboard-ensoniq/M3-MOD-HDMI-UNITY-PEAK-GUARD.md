# M3 experiment: MOD PCM full-level HDMI mix with -2 dBFS sample-peak ceiling

**Branch:** `petar/m3-mb-timing-prodos-suite-20261123`  
**Production baseline (DO NOT change):** `petar/m3-sd-sector-burst-20261123`.

## Hardware findings motivating the change

On a real a2n20v2-Enhanced M3, six-voice dual-AY Mockingboard music was
audible on both stereo channels in Original and Enhanced DOC modes. Live
switches of Original/Enhanced and IIgs 1 MHz/2.8 MHz worked while playing.
Concurrent BL616 HxCMOD jukebox playback worked, but sounded quieter.

M3 already has independent MOD post-render gain, 0..12 dB in 1 dB steps
(default +8 dB) and a **stereo-linked, per-256-frame, -2.0 dBFS sample-peak
limiter** (`mcu_mod_gain.c`). The final FPGA mixer then applied `>>> 1`
to MCU PCM for a further -6.02 dB. At the MCU peak limit (+/-26028), this
caused an approximately -8 dBFS final MOD-only sample peak.

## Changes isolated to this experiment

1. New `boards/a2n20v2-Enhanced/hdl/mcu_pcm_hdmi_mix.sv`: add MCU
   stereo PCM at **unity**, after the existing AY/DOC/SSI gain stages.
   No new gain in the MCU, no DOC oscillator or sample RAM interaction.
2. When MOD PCM is zero on both channels, pass the *original final native
   audio samples exactly*, preserving existing MB/DOC/SSI levels.
3. While MOD PCM is present, apply a signed per-channel **hard ceiling of
   +/-26028 (-2.0 dBFS sample peak)** to the combined stereo sum, and flag
   an over-peak event if **either** channel attempts to exceed the ceiling.
4. OR combined over-peak events into the existing one-second HDMI clipping
   history, which already samples at 44.1 kHz.
5. Register the module in the Enhanced Gowin project.
6. On this experiment branch ONLY, permit the existing protected M3 FPGA
   build helper to run on the isolated branch, without relaxing firmware
   flashing protections. No Stage1/Stage2/MCU changes are needed.

## What this is NOT

The +/-26028 bound is a **hard digital peak guard**, not a lookahead
compressor or transparent true-peak mastering limiter. When a loud MOD and
loud Mockingboard are summed with correlated peaks, the combined waveform
can hit the ceiling frequently and sound distorted. If that happens,
reduce MOD `PCM GAIN` temporarily and design a **stereo-linked adaptive
master bus gain stage** with attack/release and a peak/overrange counter.
A limiter cannot make two independent -2 dBFS sources add to -2 dBFS
without attenuating one/both during overlap.

The -2 dBFS value here denotes **sample peak**; it is not LUFS and does
not certify intersample/HDMI true-peak headroom.

## Compile/test from experiment checkout

PowerShell 5.1, in a **separate directory** from known-good M3:

```powershell
$lab = 'C:\AppleIIgsDev_02\a2fpga-m3-hdmi-lab'
git clone --branch petar/m3-mb-timing-prodos-suite-20261123 --single-branch https://github.com/ppuskari/a2fpga_core.git $lab
Set-Location $lab
.\Build-M3-FPGA.ps1 Check -Offline
.\Build-M3-FPGA.ps1 Script -Offline
```

If SynthLAB piano source is missing on a clean checkout, provide the
verified local disk via `-SynthLABDisk <full-path-to-synthLAB.po>`. Do not
bypass the fail-closed ROM preparation.

If Icarus Verilog is installed locally, test the exact standalone module:

```powershell
$root = 'boards/a2n20v2-Enhanced'
iverilog -g2012 -Wall -s tb_mcu_pcm_hdmi_mix -o m3_pcm_mix.vvp "$root/hdl/mcu_pcm_hdmi_mix.sv" "$root/tests/tb_mcu_pcm_hdmi_mix.sv"
if($LASTEXITCODE -ne 0){throw 'Mixer RTL test compilation failed'}
vvp m3_pcm_mix.vvp
if($LASTEXITCODE -ne 0){throw 'Mixer RTL test failed'}
```

Use the existing working M3 Gowin CLI, for example:

```powershell
.\Build-M3-FPGA.ps1 Build -Offline -GowinCli '<full-path-to-gw_sh.exe>'
```

**Program FPGA volatile SRAM only** for the first test. Do not reflash
FPGA configuration flash, BL616 Stage1 or MCU Stage2. The production
M3 software path and SD-burst portal are unmodified.

## Physical validation matrix

1. **MOD alone**, MB silent, at 1 MHz: same source and console `PCM GAIN`
   value as prior M3, expected up to +6.02 dB final output level.
2. **MOD alone**, IIgs 2.8 MHz: same result; no underruns or audible change.
3. **Dual six-channel AY + MOD** in Original mode: confirm balanced stereo,
   listen for crunching and watch combined HDMI clip-history events.
4. **Dual six-channel DOC + MOD** in Enhanced mode: same checks.
5. Hot-switch 1/2.8 MHz and Original/Enhanced while both streams are active.
6. MOD stop/mute: pre-existing native sound must remain bit-identical.
7. Compare HDMI recordings for sample peaks, RMS/loudness and clipping
   event frequency; adapt the master stage if overlap clips persist.

## Verification status

Source-level logic and a new Icarus testbench are committed. A dedicated
GitHub Actions workflow compiles/simulates the new RTL and builds the
unchanged MCU gain test on Linux. **No local Gowin synthesis, timing
closure, new FPGA bitstream or post-change hardware listening result has
been claimed.** Keep the original M3 golden FPGA firmware safe.
