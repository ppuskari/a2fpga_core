# SSI-263 speech P4 — valid write-data strobe correction

**Branch:** `petar/mb-ssi263-speech-p4-valid-write-strobe-20261107`
**Parent:** P3 capture diagnostics. Not the independent DOC piano P4 branch.

## Verified root cause

Hardware P3: after `POKE 50243,128`, reads gave
`write_count=1, last_reg=3, last_data=165, internal_R3=165, powered=0`.
Decimal 165 = $A5, the preceding P3 diagnostic signature. The Apple
bridge in `hdl/bus/apple_bus.sv` obtains the address and R/W before the
CPU data byte. Its IO_READ_DATA state only later clocks `data_r` and
asserts `a2bus_if.data_in_strobe`. The previous speech write
edge-detection triggered as soon as PHI0/slot-selection was active,
sampling a stale data byte.

P4 threads `a2bus_if.data_in_strobe` from Mockingboard into
`ssi263_slot`, and captures the register/data only on the first
validated strobe in the current write. The existing P3 diagnostic
registers, SSI timer, phoneme ROM, AY audio and VIA CA1 wiring remain
unchanged. The regression test sends a stale $A5 during early
slot-selection and only presents the actual CPU byte when the strobe
asserts.

## Deployment

PowerShell 5.1, **one command per copy/paste**:

```powershell
git clone --branch petar/mb-ssi263-speech-p4-valid-write-strobe-20261107 --single-branch https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-ssi263-speech-p4
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-ssi263-speech-p4
```

```powershell
py -3 tools\generate_ssi263_voice.py
```

```powershell
(Get-Content .\boards\a2n20v2-Enhanced\hdl\ssi263_voice.mem | Measure-Object -Line).Lines
```

Expected 8192 lines. Open
`boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj` in
Gowin, run synthesis, P&R/timing and bitstream generation.
Program **FPGA only**, not BL616. Keep previous bitstreams.

## BASIC after fresh boot (slot 4)

Run each line individually:

```basic
PRINT PEEK(50243)
```

Expected 165.

```basic
POKE 50243,128
```

```basic
PRINT PEEK(50241),PEEK(50245),PEEK(50246),PEEK(50247),PEEK(50244)
```

Expected `1 3 128 128 0`.

```basic
POKE 50240,192
```

```basic
POKE 50243,112
```

```basic
PRINT PEEK(50241),PEEK(50245),PEEK(50246),PEEK(50247),PEEK(50244),PEEK(50248),PEEK(50240)
```

Expected `3 3 112 112 1 1 128` once the timer expires.

Note: Right VIA CA1 IFR requires appropriate PCR/IER programming.
After digital diagnostics pass, boot Mockingboard Demo Disk 1 and
run speech menu option A to test original MESS playback.
