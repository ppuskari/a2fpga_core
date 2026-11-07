# SSI-263 Speech Demo Disk 1 — FPGA build P1

Experimental source branch: petar/mb-ssi263-speech-demo-fpga-p1-20261107
Parent: petar/mb-ssi263-kue-m-isolated-20261106.
Hardware: Apple IIe, A2N20v2 Enhanced, Tang Nano 20K FPGA.
BL616: existing firmware unchanged, no MCU firmware rebuild/flash required.

## Evidence from the exact DOS 3.3 disk

S/ONLY loads TEXT TO SPEECH, the MKB pronunciation rule tables, and SPEECH.
SPEECH option A selects SPEECH DEMO.
SPEECH DEMO loads COMPOSITE DRIVER at $6D00 and MESS at $5000, then
CALL 27904 ($6D00). It polls PEEK(255) for completion.

COMPOSITE DRIVER uses SSI socket $C440-$C444. Crucially it enables
the RIGHT VIA CA1 interrupt by writing $82 to $C48E and acknowledges
right VIA IFR bit 1 using $02 to $C48D. The P0 branch mistakenly wired
speech A/R to LEFT VIA CA1; P1 corrects this.

The MESS file is 5028 bytes. First phrase at $5000 is 517 total bytes:
103 five-byte SSI commands following the 2-byte length. The original
per-phoneme records are R4,R3,R2,R1,R0, streamed in reverse register
order by a 6502 loop using STA $C440,X for X=4 down to 0.
First three original records are:
    E8 7F A8 6F 60 — L (R0 code $20)
    E8 6E A8 63 88 — A (R0 code $08)
    E8 5D A8 5B 44 — YI (R0 code $04)

Run the exact disk inspector on your own disk file:
    py -3 tools\inspect_mb_speech_dsk.py C:\path\to\mockingboard1.dsk

## What P1 implements

The original P0 digital interface, SSI register addresses, status D7,
phoneme timer, powerdown and A/R logic are retained. P1 adds a
phoneme-start pulse for repeated phonemes and repairs right VIA CA1.

The voice is generated exclusively in the FPGA, not BL616. A deterministic
Python tool builds an ORIGINAL (non-proprietary) 8192-byte 64x128 signed
PCM timbre ROM using broad English formant approximations. A 16kHz
FPGA DDS pitches the sound, an LFSR gives fricatives live non-looping
noise, and the SSI-263 register 3 amplitude scales the output. Mono
16-bit speech PCM is injected into both HDMI channels through a
saturating audio mixer alongside existing native AY, DOC and speaker.

This is an experiment, NOT a silicon-authentic SSI-263 formant model.
Intelligibility, consonant transitions, actual phoneme lengths, and
audio level need a real-hardware recording.

## Morning Windows build

Clone into a SEPARATE checkout rather than overwriting the piano branch.

    git clone --branch petar/mb-ssi263-speech-demo-fpga-p1-20261107 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-speech
    Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-speech
    py -3 tools\generate_ssi263_voice.py

Generated ROM:
    boards\a2n20v2-Enhanced\hdl\ssi263_voice.mem

Verify there are exactly 8192 hex lines:
    (Get-Content .\boards\a2n20v2-Enhanced\hdl\ssi263_voice.mem | Measure-Object -Line).Lines

Open this Gowin project:
    boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj

Run Gowin Synthesis, P&R, timing checks and Bitstream Generation.
Program the FPGA bitstream ONLY; do not flash/downgrade BL616.
The shipped slots.hex maps Mockingboard to slot 4. The DOS speech
driver hardcodes $C4xx, so a changed runtime slot assignment must
be returned to slot 4.

## Running the supplied DOS disk

Boot the same mockingboard1.dsk and enter the speech menu. Or from
a DOS 3.3 prompt enter:

    RUN S/ONLY

Choose A — MESSAGE. This runs SPEECH DEMO automatically.
A direct RUN SPEECH DEMO also loads MESS and COMPOSITE DRIVER.
The first message begins with the sequence for "Ladies and gentlemen".
Each next phoneme should arrive via a right-VIA CA1 interrupt, and
speech should be audible on BOTH HDMI channels. Compare with original
SSI-263 hardware if available; expect an approximate robotic voice.

## Automated verification and limits

The GitHub Actions speech workflow generates the timbre ROM, checks
SSI-263 register/status/A-R behavior and powerdown PCM, replays the
original MESS opening three phonemes L/A/YI, verifies the first
two request timings, lints the HDL and checks right VIA CA1 wiring.
These are hardware-independent tests: NOT Gowin timing closure, exact
audio quality, full runtime disk execution, or a hardware confirmation.

Separate from P4 DOC multisampled piano: do not merge either branch
into a working a2fpga firmware tree without further regression.
