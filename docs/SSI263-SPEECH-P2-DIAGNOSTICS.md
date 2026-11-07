# SSI-263 P2 — hardware diagnostics

Branch: `petar/mb-ssi263-speech-p2-diagnostics-20261107` (based on P1). FPGA-only. **Do not reflash BL616 MCU.**
Preserves AY audio, SSI control writes, IRQ behavior, phoneme synthesis and HDMI mixing.
This is deliberately a diagnostic build, not an unverified handshake fix.

## Registers (slot 4)
The normal SSI status remains at `$C440` (decimal 50240).
Only CPU **reads** of the following addresses are overlaid; CPU writes still
reach the original SSI-263 control registers.

| Apple address | BASIC decimal | Return value |
|---|---:|---|
| $C440 | 50240 | original SSI ready D7 status, 0 or 128 |
| $C441 | 50241 | CPU SSI write pulses counted, saturated at 255 |
| $C442 | 50242 | Apple PHI/XCK ticks counted, saturated at 255 |
| $C443 | 50243 | constant 165 ($A5) read-path signature |
| $C444 | 50244 | powered-on flag bit 0 |
| $C48D | 50317 | **right** VIA IFR; CA1 flag is bit 1 (value 2) |

Diagnostic counters reset when the FPGA resets or the SSI socket is disabled.

## Reproduce BASIC test

Boot to Applesoft after loading this FPGA bitstream, with the Mockingboard
configured in slot 4. These lines use **BASIC decimal addresses**:

```basic
PRINT PEEK(50243)
PRINT PEEK(50241),PEEK(50242),PEEK(50244)
POKE 50243,128
POKE 50240,192
POKE 50243,112
PRINT PEEK(50241),PEEK(50244)
FOR I=1 TO 2000:NEXT I
PRINT PEEK(50240),PEEK(50241),PEEK(50242),PEEK(50243),PEEK(50244),PEEK(50317)
```

Expected signature = 165, write count >=3, powered = 1,
XCK = 255, status eventually = 128 and right VIA IFR bit 1 = 1
(provided CA1 active-edge polarity was configured appropriately).

Interpretation:
- Signature absent: FPGA bitstream / card address decode / read-data selection.
- Signature present but write count unchanged: slot write-strobe capture.
- Writes present but powered = 0: SSI command/state sequencing.
- Powered = 1, XCK not increasing: timebase clock signal.
- Powered and XCK valid, status never ready: timer/control sequencing.
- SSI status ready but right VIA CA1 IFR bit 1 absent: CA1 edge/polarity or
  VIA config; explicitly program PCR/IER before relying on interrupts.

**Important qualification:** right VIA IFR flag bit 1 latches on the
configured CA1 edge. The test above alone does not ensure that the VIA
PCR/IER is configured like the actual speech driver. Do not diagnose CA1
from an unrelated IFR byte without checking the PCR.

## Build
1. `git clone --branch petar/mb-ssi263-speech-p2-diagnostics-20261107 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p2`
2. `cd C:\AppleIIgsDev_02\a2fpga-ssi263-p2`
3. `py -3 tools\generate_ssi263_voice.py`
4. Check `boards\a2n20v2-Enhanced\hdl\ssi263_voice.mem` is exactly 8192 lines.
5. Open `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj` in Gowin,
   synthesize, place-and-route, verify timing, and generate bitstream.
6. Program FPGA only; keep prior P1/P4 bitstreams for rollback.

The simulation test `tests/mb_ssi263/tb_ssi263_demo.sv` covers signature,
write count, powered bit and saturating XCK count, as well as the P1
initial-phoneme/ready sequence. It is not a physical FPGA or Gowin test.
