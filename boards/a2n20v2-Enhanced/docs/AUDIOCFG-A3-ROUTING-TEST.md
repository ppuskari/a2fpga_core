# AUDIOCFG A3 — Runtime boot audio routing and experimental native DOC

Branch: `petar/audiocfg-a3-runtime-audio-20261116`
Base: validated A1/A2 four-mode menu, originally forked from M641 golden.
The M641 and MB6.6 development branches are untouched.

## Scope and ownership

The FPGA has **one** DOC5503 renderer and one waveform memory bank pair.
A3 changes audio ownership only at cold startup. The BL616 writes SPI
register `0x6F` before the slot-map `0x6B` strobe. Afterwards the FPGA
rejects mode changes until its own device reset; saving menu changes
alone never reconfigures a playing DOC.

| Saved code | Menu | Mockingboard bus | DOC host owner | Audible source |
|---|---|---|---|---|
| 0 | Enhanced MB | yes | M641 AY-to-DOC translator | DOC piano/FX + hybrid SSI263 |
| 1 | Original MB | yes | none | two YM2149 PSGs + hybrid SSI263 |
| 2 | Native DOC | no | native Apple CPU | DOC, no MB/SSI263 |
| 3 | Shared | yes | native Apple CPU | two YM2149 PSGs + native DOC + hybrid SSI263 |

The Shared mode uses the original YM2149 path and **not** the
AY-to-DOC translator, so the native player exclusively owns DOC
oscillators and waveform RAM. It does not implement a simultaneous
DOC-enhanced Mockingboard and Native DOC.

Native/Shared HDMI uses the baseline native +3dB calibration; Enhanced
retains the exact M641 8x/-2dB limiter and speech pre-compensation.
Do not switch modes without a complete cold reboot.

## Native IIe slot transport — first hardware implementation

The current virtual Mockingboard slot is typically Slot 4.
Address translation tracks the configured virtual slot (`C0n0` through
`C0nF`, where `n` is the selected slot). For Slot 4:

| IIe address | Read | Write |
|---|---|---|
| `$C0C0` | Sound GLU control register | Sound GLU control / volume |
| `$C0C1` | DOC register mirror / last Sound RAM data | DOC register or waveform byte |
| `$C0C2` | Address pointer low | Address pointer low |
| `$C0C3` | Address pointer high | Address pointer high |
| `$C0C4`–`$C0C6` | ASCII `D`, `O`, `C` | ignored |
| `$C0C7` | protocol byte `$11` (initial register-mirror interface) | ignored |
| `$C0C8` | `$A2` native / `$A3` shared | ignored |
| `$C0C9` | 128K extension state (`$10/$11/$13`) | ignored |

The register window `$C0C0`–`$C0C3` has IIgs Sound GLU write semantics
for `$C03C`–`$C03F`: `$C0C0` bit 6 selects Sound RAM vs DOC register
access, bit 5 auto-increments the pointer, low nibble controls volume.
The 128K unlock protocol remains `A2FP`/lock at DOC addresses E2-E6,
with extension bank rules unchanged.

On a *real IIgs host*, selecting Native/Shared also enables ordinary
`$C03C`–`$C03F` CPU writes. The IIe-only slot path remains separate
from the regular Mockingboard VIA range `$Cn00`–`$CnFF`.

**Compatibility limitations requiring A4 hardening:**

- DOC oscillator register reads are a writeback mirror (initialized at
  power-up and scrubbed after Apple reset); asynchronous internal DOC
  changes to oscillator registers are not yet reflected.
  E1 oscillator enable reads return the DOC's live enable state.
- Sound RAM reads currently return the last staged data byte, *not*
  the addressed SDRAM contents. Real RAM readback plus a bounded
  transaction/ready protocol must be implemented before data integrity
  or full IIgs native-driver parity can be claimed.
- DOC register reads are also issued to the DOC core to preserve its
  own read handling, but the CPU receives the mirror because DOC
  internal response latency is not bounded to the 1MHz bus cycle.
- Native DOC and Shared audible playback **require the Apple program to
  upload waveforms and initialize oscillators**; there is no default
  sample-bank preload in those modes.
- This is not yet a fully verified 65C02 application ABI or tool set.
  In particular, the planned SenseiPlay/NTP port remains a later step.

## First physical test sequence

0. KEEP the known-good M641 FPGA+MCU images on a recovery stick.
1. Run the usual generated ROM prep (SynthLAB piano and SSI263 voice).
   Build the FPGA from this A3 branch with Gowin. Check resource
   utilization and **timing violations** before flashing. Build and
   install the matching `firmware_host` BL616 MCU; only Stage 2 at
   `0x40000` should ever be flashed by a PC tool.
2. Start in saved mode 0 (Enhanced), cold power cycle. Expect console
   `AUDIOCFG A3: REQ=0 ACK (BOOT ROUTING)`. Play the exact M641 title
   and SSI263 speech tests, including TAB responsiveness.
3. Select mode 1 (Original), save via DOWN+ENTER, and cold power cycle.
   Expect `REQ=1 ACK`. Play the MB disk. YM2149 chip tones/noise,
   envelope, VIA IRQ and SSI263 should sound. Piano is *not* expected.
4. Select mode 2 (Native), save and cold power cycle. In Applesoft BASIC
   on the IIe with the card in Slot 4, the read-only probe is:

       PRINT PEEK(49348);PEEK(49349);PEEK(49350);PEEK(49351);PEEK(49352)

   Expected decimal results: `68 79 67 17 162`.
   The Mockingboard VIA should no longer drive the bus or IRQ.
   No native audio is expected before the client loads waveforms.
5. Select mode 3 (Shared), save and cold power cycle. The same probe
   should return `68 79 67 17 163`; MB music and SSI263 must
   remain available while native DOC registers are separately
   accessible from the device-space port.
6. Save Enhanced mode (0), reboot, and repeat M641 regression test.
7. With each mode, inspect HDMI initialization, storage boot, Hub/USB
   keyboard TAB input, video, and DOC diagnostics.
8. If any failure occurs, report selected mode, FPGA/MCU build stamps,
   console `AUDIOCFG` line, and which phase failed. Reflash known-good
   FPGA/MCU images without touching Stage 1.

## Build status

Source implementation committed and visually reviewed. No Gowin,
T-Head/BL616 build, timing closure or physical hardware tests have
been executed by ChatGPT in this branch. Do not promote or merge into
MB6.6 until these are complete. 
