# P1 checklist — Exclusive DOC mode and Mockingboard compatibility

Project branch: `petar/mockingboard-ensoniq-p0`.
Golden parent: `eb6d2726fd252a54fe84739cb767361adf11d657`.
Design agreement: [ADR-0001](ADR-0001-EXCLUSIVE-DOC-OWNERSHIP.md).

## Outcome to prove

One validated Ensoniq DOC instance, with exactly one register-owning frontend:
- Default `GS`: *unchanged* native Sound GLU/Tool225.
- Experimental `MB-DOC`: dual VIA/AY hardware interface; eventual bridge owns DOC and sample RAM.

P1 starts with register/IRQ emulation and host ownership plumbing; **no claim of audible sampled Mockingboard until P3**.

## Stage 1: Static configuration and compatibility

- [ ] Add `AUDIO_MODE_MB_DOC` top-level build parameter (conceptual, not yet in HDL), default 0. Pin GS/MB ownership to this choice at synthesis; no runtime switching.
- [ ] Preserve all current golden parameters, native GS audio pipeline and 128K status behavior when mode 0.
- [ ] In mode 1, enable the Mockingboard personality only, through card ID 2 in slot 4 as mapped by `hdl/slots/slots.hex`. Confirm effective slot mapping after MCU initialization.
- [ ] Verify both 6522 VIA register read/write and PB BDIR/BC/RESET, PA AY register addressing/data.
- [ ] Verify separate left and right AY readback/logic, timer IRQ and reset behavior.
- [ ] Capture per-chip AY register **event** intents from VIA port/control writes. Existing `YM2149.sv` samples BDIR/BC/DI on *every* 54 MHz rising clock, not CE. Handle held write phases without spurious events, and repeated register 13 envelope retriggers.
- [ ] Leave YM2149 emulation available for software compatibility/reference. Route **no** YM2149 PCM to enhanced HDMI output.

## Stage 2: True one-DOC host ownership

- [ ] Split native GS host write permission from `sound_glu.ENABLE` so DOC clock and SDRAM oscillator fetches remain operational in MB-DOC mode.
- [ ] Provide **one** synchronous DOC `cs_n`, `addr`, `data` host interface, selected at synthesis between GS Sound GLU and MB-DOC translator. Explicitly latch address/data for the transaction; audit the current use of live `a2bus_if.data`.
- [ ] GS writes to $C03C-$C03F must neither alter DOC registers nor overwrite the patch sound RAM in MB-DOC mode.
- [ ] Preserve waveform fetch `DOC_MEM_PORT`, the sound RAM base, 7 MHz timing enable, `sg_audio_l/r`, CDC, audio_out and HDMI gain stage.
- [ ] Do not set `sound_glu.ENABLE=0` in MB-DOC mode: it would also disable oscillator sound RAM reads.
- [ ] Define a **separate** waveform preload and DOC register initialization sequence for MB-DOC mode (P3); no oscillator enable until the patch bank is loaded.

## Stage 3: Verification gates

- [ ] Simulate DOC host mux and prove never two owners; GS and MB test vectors both generated.
- [ ] Simulate repeated AY pitch/volume/mixer/envelope transitions including register-13 retrigger.
- [ ] Run Gowin synthesis and PnR for default GS and experimental MB-DOC selection; record resource/timing versus [golden report](RESOURCE-BASELINE.md).
- [ ] In GS personality run native IIgs DOC and 128K status/bank/Tool225 streaming regression; do not expect Tool225 audio in MB-DOC mode.
- [ ] On Apple II/IIgs in MB-DOC mode detect Mockingboard in slot 4, read/write AYs and verify VIA timer interrupts.
- [ ] Archive .fs hash, tool version, commit SHA and logs; keep a recovery golden .fs.

## P2 event contract

Decode AY events with `chip[0..1]`, `register[0..15]`, `value[7..0]` and a timestamp/tick to drive a software-tested bridge. Tone period is 12 bits, pitch/period zero need validation, mixer bits separately control tone/noise, reg 13 retriggers the envelope, and there are six logical stereo voices. An arbitrary AY game contains no sampled instrument metadata; patch selection is an explicit policy.

**Important:** This project does not implement a second wavetable audio renderer. The bridge writes the existing `doc5503` registers and uses preloaded native DOC waveform RAM.
