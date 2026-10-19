# P1 checklist — Mockingboard compatibility front-end

Project branch: `petar/mockingboard-ensoniq-p0`.
Golden parent: `eb6d2726fd252a54fe84739cb767361adf11d657`.

## Goal

Enable and validate the **software-visible** Mockingboard (dual 6522 VIA, dual AY/YM2149 register interface and IRQ) before changing any audio rendering. This stage is intentionally a silent bring-up for the new sampled renderer, not a release-quality sound build.

## Change boundaries

- [ ] Add a separately named, disabled-by-default experimental build setting to `boards/a2n20v2-Enhanced/hdl/top.sv`.
- [ ] Confirm slot 4 has card ID 2 in `hdl/slots/slots.hex` (currently `00 00 03 05 02 04 06 01`); avoid changing other slot mappings.
- [ ] Verify 6522 register read/write, PB BDIR/BC and RESET, PA register addressing/data.
- [ ] Preserve the left and right AY chip register paths and timer IRQ timing.
- [ ] Capture per-chip AY-register-write intent from VIA port/control transitions. YM2149.sv samples BDIR/BC/DI each rising CLK edge, independently of CE, which only advances synthesis. Validate handling of held write phases and deliberate repeated register-13 writes (envelope restart).
- [ ] Leave YM2149 cores present for readback/comparison while they are not connected to HDMI in enhanced mode.
- [ ] Keep `sound_glu.sv`, `doc5503.sv`, waveform RAM protocol, Tool225, MCU/BL616 firmware, and native Ensoniq audio path unchanged.
- [ ] Collect pre/post Gowin synthesis utilization and PnR timing.
- [ ] Archive .fs SHA256, build commit SHA and deterministic test logs.

## Suggested hardware regression

- [ ] ROM 3 IIgs with A2N20v2-Enhanced, regular GS/OS audio still works.
- [ ] Slot-4 Mockingboard software discovery and register readbacks succeed.
- [ ] VIA timer IRQ vectors/timing survive repeated starts and stops.
- [ ] Separate left/right AY commands can be decoded.
- [ ] DOC 128K extension unlock/status and bank data unchanged.
- [ ] Tool225 playback and STOP/replay still pass.
- [ ] Existing golden bitstream can be reflashed as a recovery baseline.

## P2 handoff contract

The next module accepts a decoded event `(chip[0..1], ay_reg[0..15], value[7..0], tick)`, plus reset, and exports a six-channel voice-state snapshot. Each channel's tone period is a 12-bit combination of coarse/fine registers; mixer bits gate tone/noise separately; volume register bit 4 selects AY envelope control; channel allocation is 3L/3R. Establish precise clock ratios, held-bus write semantics and envelope semantics by comparing with the actual `hdl/support/YM2149.sv` source and traces, not an assumed generic AY implementation.

**Do not** connect the two 10-bit `mb_audio_l/r` buses directly to the audio mixer and call it the Ensoniq renderer: that only reproduces the old PSG sound.
