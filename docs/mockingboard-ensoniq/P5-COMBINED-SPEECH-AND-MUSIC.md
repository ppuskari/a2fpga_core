# Mockingboard DOC music P4 + SSI speech P5: combined integration candidate

Branch: `petar/mb-doc-p5-speech-p5-combined-20261107`

## Inputs and ownership

- Music foundation: `petar/mb-doc-p4-mcs-articulation-rest-multisample-20261107`
  - Seven SynthLAB sustain zones and MCS piano articulation/retrigger
  - Period-0/1 rest muting
  - Original AY tone/noise FX bypass for title sequence
  - A440 calibrated DOC frequency mapping
  - IMPORTANT: music's **8x final HDMI level adjustment with -2 dBFS limiter** and existing clipping history are retained verbatim
- Speech source: `petar/mb-ssi263-speech-p5-voice-profiles-20261107`
  - Hardware-proven SSI write capture using Apple bridge `data_in_strobe`
  - SSI phoneme timing, status D7 and right VIA CA1 interrupt wiring
  - Selectable voice profiles: 0=P4 raw reference, 1=enhanced 2x gain and smoothed/noise-reduced output
  - P3 SSI diagnostic readbacks

This is **not a git merge of divergent branches**. Music P4 is the
base, with selected speech HDL, testbench and generator imported.
The original music and speech branches stay untouched.

## Output mixing: avoid accidental 8x speech boost

Music P4 already selects DOC audio or native AY FX separately per
channel and applies the **8x gain at the final HDMI output** in
`AUDIO_MODE_MB_DOC`. SSI speech P5 was built without that music gain
stage. In combined mode the SSI output is divided by 8 (arithmetic
shift by three) before combining with the selected music signal.
A 17-bit signed sum is saturated to 16-bit for each channel.
Thus the P5 speech profile is not inadvertently boosted by another 8x.
This is an initial gain balance, NOT a guarantee of equal perceived loudness.
The final music output limiter still applies to the combined signal and
may show clipping if DOC, AY FX and speech peak at once.
No changes to the speech command timer or the music DOC command bridge.

## FPGA configuration

`boards/a2n20v2-Enhanced/hdl/top.sv` defaults:

- `MOCKINGBOARD_SSI263_ENABLE=1`
- `MOCKINGBOARD_SSI263_VOICE_PROFILE=1` (enhanced)
- Existing music `AUDIO_MODE_MB_DOC` and related P4 parameters unchanged.
- Normal non-MB-DOC HDMI gain path unchanged.

Voice profile 0 versus 1 is a **compile-time** selection, not an MCU or
Apple II software setting yet.

## One command per paste — Windows PowerShell 5.1

```powershell
git clone --branch petar/mb-doc-p5-speech-p5-combined-20261107 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-speech-p5
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-speech-p5
```

```powershell
py -3 tools\extract_synthlab_piano.py --download
```

```powershell
py -3 tools\generate_ssi263_voice.py
```

```powershell
(Get-Content .\boards\a2n20v2-Enhanced\hdl\piano_multisustain.mem | Measure-Object -Line).Lines
```

Expected **1408** hexadecimal 32-bit words (5632 bytes represented).

```powershell
(Get-Content .\boards\a2n20v2-Enhanced\hdl\ssi263_voice.mem | Measure-Object -Line).Lines
```

Expected **8192** hexadecimal 8-bit phoneme bytes.

```powershell
git log -1 --oneline
```

Open:
`boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj`

Run Gowin synthesis, P&R, verify timing closure and resource usage,
then generate and program **FPGA only**. Do **NOT** flash BL616.
Preserve both prior standalone P4 music and P4/P5 speech bitstreams.

## Hardware acceptance sequence

1. Boot Mockingboard Demo Disk 1. Check title text explosions, rising
   sweep, and AY timing: compare against prior music P4.
2. Test KEYBOARD A–K (pitch and natural envelope), MCS SUGAR2,
   MINUTE and WEASEL: verify notes, articulation, rest and overall level.
3. Run `RUN S/ONLY`, choose A MESSAGE. Check first phrase
   starts and advances, right VIA CA1 does not hang, speech level.
4. Compare simultaneous or consecutive speech/music: check peaks,
   clipping-history indicator and any source-switch clicks.
5. Only promote to **combined golden** after Gowin timing passes and
   both sound paths are validated on real hardware.

## Automated test caveat

The new `.github/workflows/mb-doc-speech-combined.yml` performs
isolated SSI register/audio simulations and static source/mixer checks.
It does **not** replace Gowin P&R, full six-voice audio simulation,
or a recording from physical Apple II hardware.
