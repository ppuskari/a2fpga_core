# Other-session baseline handoff (DO NOT MODIFY)

Verified Apple IIe a2n20v2-Enhanced audio branch:
`petar/audio-m641-a3-hwvalidated-20261117`

Exact commit: `b7ea7f6af45ac719062cdacfe2790b98c92567dd`

User hardware confirmation on November 17, 2026:
- Cold physical power-on loads persisted Original AY and Enhanced DOC separately.
- Early SPI diagnostic `S1 FF/FF BAD`, before-reset retry `S1 A1/D1 OK`.
- Original AY level calibration now satisfactory (gain +21.98 dB into -2dBFS ceiling).
- Live FPGA mode switching Original↔Enhanced works while demo music is playing, no Apple reset.
- SSI263 speech remains functional.
- Actual configuration screen boot snapshots remain visible.
- Native and Shared modes have not yet been proven on hardware.

Future M6.6/128K Mockingboard FX experiments may branch from this known-good
MCU/FPGA mode-selector commit but must not alter this snapshot branch.
Sensei8 software branch must not touch MCU/FPGA sources until native DOC
slot testing requires a separately reviewed, isolated hardware change.