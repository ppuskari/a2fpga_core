# P1 HDL implementation notes

2026-10-19 — experimental branch `petar/mockingboard-ensoniq-p0`.

**State:** P1 structural HDL committed; **not compiled, simulated or tested on hardware** in this environment. This is an engineering checkpoint, **not a flash-ready new bitstream**. Native GS is still the default.

## Source changes

### `boards/a2n20v2-Enhanced/hdl/top.sv`

- Adds `AUDIO_MODE_MB_DOC` mode parameter, default 0 for native IIgs GS sound.
- `MB_DOC_EXPERIMENT` compile define opts the parameter's default to 1 without editing source. A Gowin top-level parameter override is an alternative.
- In MB mode, enables the existing Mockingboard instance (card ID 2; default slot 4 via `slots.hex`).
- Connects two independent AY register-write event outputs from the Mockingboard module, 4-bit register ID and 8-bit value per chip.
- Passes `MB_DOC_MODE` into `sound_glu` and connects a **safe, inactive** MB DOC command port: `mb_doc_wr_w=0` and 8-bit address/data zero. These are deliberate P1 placeholders.
- Leaves audio mixing unchanged: `core_audio_l_w/r_w = sg_audio_l/r` only. No YM2149 PCM is mixed.

### `hdl/sound/sound_glu.sv`

- Adds `MB_DOC_MODE` parameter, default 0.
- Gates only the GS host's `glu_sel_w` when MB mode is selected.
- Adds `mb_doc_wr_i`, `mb_doc_addr_i`, `mb_doc_data_i` and an exclusive mux in front of the **existing** `doc5503`.
- GS selection retains the exact original `doc_wr_r`, `doc_addr_r` and live `a2bus_if.data` paths.
- Does **not** gate DOC oscillator clock, `doc_mem_if.rd`, SDRAM data return or the existing sound mixer.
- MB mode currently uses native bank 0; dynamic 128K patch-bank initialization is still future work.

### `hdl/mockingboard/mockingboard.sv`

- Preserves dual 6522 VIA and YM2149 instances with readback and IRQ behavior.
- Adds one `mb_ay_capture` per chip, outputting a one-cycle event when a completed BDIR=1/BC=0 data-write phase ends.
- Tracks the selected AY register during BDIR=1/BC=1 address phases and samples data during write phase.
- Allows repeated *identical* register-13 write phases to generate independent events, required for AY envelope retriggers.
- Resets capture state on system reset, PSG reset or disable; the existing YM2149 core controls the actual software-visible AY register readback.
- A future compatibility case is VIA PA rewrites while the bus write phase remains asserted; this has not been captured as multiple transactions and must be characterized before claiming total fidelity.
- Uses `MB_AY_CAPTURE_UNIT_TEST` guard to isolate the capture module for unit testing.

## Run targeted AY capture test

From the repository root, with Icarus Verilog and vvp installed:

```sh
sh tests/mb_doc/run_capture_test.sh
```

Equivalent direct commands:

```sh
iverilog -g2012 -Wall -DMB_AY_CAPTURE_UNIT_TEST \
  -s tb_mb_ay_capture -o mb_capture.vvp \
  hdl/mockingboard/mockingboard.sv \
  tests/mb_doc/tb_mb_ay_capture.sv
vvp mb_capture.vvp
```

The bench checks independent left/right channel events, held BDIR control, repeated envelope register-13 writes, invalid register IDs, reset and card disable behavior. **These tests are committed but not executed here.**

## Produce two candidate builds (after compilation environment setup)

| Selection | Parameter/define | Expected GS DOC control | Expected Mockingboard |
|---|---|---|---|
| Default | No define; `AUDIO_MODE_MB_DOC=0` | Original native | Disabled by default |
| P1 experiment | Define `MB_DOC_EXPERIMENT` or `AUDIO_MODE_MB_DOC=1` | Native host writes blocked, DOC oscillator still active | Dual VIA/AY registers in configured slot, no sampled audio yet |

Do not overwrite the golden .fs. Save each new build with a distinct name, record the Gowin tool version, synthesis/PnR reports and SHA256. Reflash the preserved August 16 .fs if any unexpected bus/GS behavior occurs.

## Required checks before P1 signoff

1. Compile the two selections and compare warnings, LUT/BSRAM/DSP and PnR timing.
2. Run the capture bench; inspect for edge and clock scheduling issues.
3. Confirm GS bitstream behaves indistinguishably from the validated release, including 128K waveform writes, stream playback and HDMI gain.
4. Test real-II slot-4 Mockingboard discovery, dual VIA timer IRQ, AY write/readback and control reset in MB mode.
5. Verify normal GS Sound GLU bus writes cannot alter the DOC in MB mode, while DOC waveform fetch remains enabled.
6. Test no invalid/double AY capture events on real game traces, especially BDIR-held port A rewrites.

## Next HDL change (P2)

Wire a bounded command sequencer to the new `mb_doc_*` inputs; deliver stable address and data for each DOC register write and deassert CS between transactions. Add a small deterministic patch uploader into **existing sound SDRAM** with complete initialization before any oscillator leaves HALT. Then translate tone-period/frequency, mixer gating, volume, envelope and noise events into six DOC voices. Because native GS is mutually exclusive, this mode may ultimately use additional DOC oscillators for samples and layering.

The committed P1 gateware is deliberately **not** audible for Mockingboard yet; do not confuse a successful register capture with a working instrument engine.
