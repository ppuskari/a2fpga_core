# SSI-263 Speech P3 — Captured-command diagnostics (FPGA only)

Derived from P2: `petar/mb-ssi263-speech-p2-diagnostics-20261107`.
Experimental A2N20v2 Enhanced Tang Nano 20K build.
**No BL616 MCU rebuild/flash required.** Do not merge with the independent
P4 DOC piano branch. Keep the last known-good FPGA bitstream for rollback.

## Motivation

Real hardware P2 observed two acknowledged SSI register writes after a fresh
boot, yet `powered=0` and `status=0`, while the XCK tick counter reached
255. P2 counted write STROBES but couldn't show what address/data were latched.

P3 adds non-destructive readback probes to see those values and the internal
R3 state. **P3 does not change the capture edge, SSI control state machine,
speech synthesis, VIA CA1 connection, or existing AY audio.**

## Readback map (configured Mockingboard slot 4)

| Address | Decimal | Meaning |
|---|---:|---|
| $C440 | 50240 | SSI original D7 ready status: 0 or 128 |
| $C441 | 50241 | Saturating SSI write count |
| $C442 | 50242 | Saturating XCK tick counter |
| $C443 | 50243 | P2/P3 diagnostic signature = 165 ($A5) |
| $C444 | 50244 | SSI powered flag: 0 or 1 |
| $C445 | 50245 | Last captured SSI register index (expect 3) |
| $C446 | 50246 | Last captured SSI data byte (expect 128, then 112) |
| $C447 | 50247 | Internal SSI R3 (expect 128, then 112) |
| $C448 | 50248 | Number of powered-state rising edges (expect 1) |
| $C48D | 50317 | Right VIA IFR; CA1 flag is bit 1 |

Read-only diagnostics overlap CPU *reads* of SSI aliases in this development
build. They do not change CPU SSI *writes*. Counters reset on FPGA reset
or card-disable. `$C448` is distinct from `$C440` in this build.

## Single-line Applesoft diagnostic, ONE LINE AT A TIME

Boot to Applesoft with slot 4 configured. Run each line separately:

```basic
PRINT PEEK(50243),PEEK(50241),PEEK(50242),PEEK(50244)
POKE 50243,128
PRINT PEEK(50241),PEEK(50245),PEEK(50246),PEEK(50247),PEEK(50244)
POKE 50243,112
PRINT PEEK(50241),PEEK(50245),PEEK(50246),PEEK(50247),PEEK(50244),PEEK(50248),PEEK(50240)
```

Expected:
- first PRINT: 165,0,255,0 (XCK counter may already be saturated)
- after POKE $80: 1,3,128,128,0
- after POKE $70: 2,3,112,112,1,1,128 (after timer expires)

If last captured address is not 3 or data not 112, focus next
revision on CPU bus-cycle data/address capture. If captured values
are right but R3 isn't 112, trace registered strobe/core handoff.
If R3 is 112 but powered stays 0, trace activation edge/control logic.

Hardware-observed actual results take priority over the simulated
idealized register-write test. The demo testbench checks the new
readbacks and prior status/PCM timing but not the complete 6502
bus/VIA interrupt execution.

## Single-line Windows PowerShell 5.1 build

```powershell
git clone --branch petar/mb-ssi263-speech-p3-capture-diagnostics-20261107 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-p3
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-p3
```

```powershell
py -3 tools\generate_ssi263_voice.py
```

```powershell
(Get-Content .\boards\a2n20v2-Enhanced\hdl\ssi263_voice.mem | Measure-Object -Line).Lines
```

Expect 8192. Open `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj`
in Gowin; synthesize, place/route, check timing, generate bitstream.
Program FPGA ONLY. No MCU firmware modifications.
