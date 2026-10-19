# Golden Enhanced PnR resource baseline

Source: `boards/a2n20v2-Enhanced/impl/pnr/a2n20v2_enhanced.rpt.txt` in `petar/doc128k-p0x-golden`.

Report is from **August 3, 2026** (Gowin PnR V1.9.9 Beta-4 Education, device GW2AR-LV18QN88C8/I7). It accompanies the preserved golden project; these numbers are **before** Mockingboard enablement or any new AY-to-DOC bridge.

| Resource | Golden use |
| --- | ---: |
| Logic | 7,243 / 20,736 (35%) |
| Registers | 4,225 / 15,915 (27%) |
| CLS | 5,441 / 10,368 (53%) |
| BSRAM | 68% |
| DSP | 58% |
| PLL | 2 / 2 (100%) |

## Exclusive-mode implication (ADR-0001)

The initial plan for a **second six-voice PCM renderer** has been superseded. This project reuses the **existing single DOC5503** rather than duplicating oscillators, interpolation, or mix hardware.

- The new hardware overhead should primarily be the AY-to-DOC event translator, patch selection, small microsequencer/host-register mux, and sample-memory preload control.
- DOC waveforms live in **existing** 64/128K sound SDRAM, controlled by one owner per bitstream; do not assume spare BSRAM is available for large wavebanks.
- Both PLLs are allocated, so keep logic in existing 54 MHz clock / 7 MHz DOC enable domains.
- No second DSP-heavy renderer is needed. Instrument layering may still increase usage through added envelope or noise logic, so remeasure.
- The existing DOC waveform read timing, SDRAM port priority, audio_out CDC and 44.1 kHz HDMI output must remain unchanged unless explicitly measured and justified.
- Baseline utilization does *not* prove that the new design meets timing closure.
- **Critical:** do not disable `sound_glu.ENABLE` to select MB-DOC ownership; that also gates the DOC's waveform fetches. Restrict GS host writes separately.

For every candidate bitstream measure logic, CLS, BSRAM, DSP, max frequency/timing, bitstream hash and audio tests against this preserved baseline. Keep GS personality golden-compatible, and do not claim MB-DOC audio until sample loading and oscillator initialization are implemented and exercised on real hardware.
