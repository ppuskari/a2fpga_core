# Golden Enhanced PnR resource baseline

Source: `boards/a2n20v2-Enhanced/impl/pnr/a2n20v2_enhanced.rpt.txt` in `petar/doc128k-p0x-golden`.

Report is from **August 3, 2026** (Gowin PnR V1.9.9 Beta-4 Education, device GW2AR-LV18QN88C8/I7). It accompanies the preserved golden project; these numbers are **before** Mockingboard enablement or any new PCM renderer.

| Resource | Golden use |
| --- | ---: |
| Logic | 7,243 / 20,736 (35%) |
| Registers | 4,225 / 15,915 (27%) |
| CLS | 5,441 / 10,368 (53%) |
| BSRAM | 68% |
| DSP | 58% |
| PLL | 2 / 2 (100%) |

Implications:

- There is logic headroom for a small register decoder and renderer, but *no new PLL resource*. Use the existing logic / audio clocks and clock-enables.
- BRAM/BSRAM is more limited than LUTs. Budget a compact PCM patch table (or explore a separately allocated SDRAM read port) rather than assuming large sampled instruments will fit on-chip.
- DSP is already 58% used. Multipliers for six sampled voices should be time-shared, restricted in width, or measured after synthesis.
- PnR percentage alone does not prove timing closure; explicitly inspect the next experimental timing reports and playtests.
- Preserve existing ENSONIQ_WORD_BASE at word 0x010000 and 128K DOC waveform protocol. Never reuse either bank for Mockingboard patches without a designed arbiter and tests.
- Final HDMI PCM is 44,100 Hz with existing audio_out and gain stages; avoid introducing a clock-domain race.

For every P1-P4 candidate, append measured post-change logic, CLS, BSRAM, DSP, timing, bitstream hash and audio tests. Do not infer device capacity from this baseline alone.
