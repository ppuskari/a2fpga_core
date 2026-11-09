#!/usr/bin/env python3
"""Produce the first fixed-point SSI-263 die-parameter FPGA coefficient ROM.

Source: Tamas Geczy's SSI263 chip emulator (MIT, 2026), vendored in
kue-m/mockingboard-pico firmware/vendor/ssi263/ssi263_defaults.h.
64 x 9 decoded die parameter bytes copied from that source; NOT waveform
samples, proprietary recorded speech or MAME SC-01 GPL glottal data.
Full provenance: docs/mockingboard-ensoniq/P7-DIE-FORMANT-R1.md

This is a *new approximate* fixed-point renderer using those die parameters:
frequencies follow the upstream capacitor-law formula; the 16 kHz digital
resonators and their bandwidth are deliberately experimental.
"""
from __future__ import annotations
import math
from pathlib import Path

OUT = (Path(__file__).resolve().parents[1] /
       "boards/a2n20v2-Enhanced/hdl/ssi263_die_formants.mem")
SAMPLE_HZ = 16000
FILTER_HZ = 19000.0
# Decoded columns F1 F2 F3 NAS VA FA b00 b01 b02, 64 codes.
DECODED = """
07090c000000010001
020e0e000c00010101
050e0d000a00010101
010d0e000b00010101
020c0b000600010101
030e0e000c00010101
010f0f000900010101
050a0c000800010101
060b0b000800010101
06090a000800010101
09080b000800010101
0a090b000800010101
0d090b000600010101
0f070b000600010101
0f030b000600010101
0f040b000700010101
0d020a000600010101
07010b000800010101
05010b000900010101
08020a000800010101
03060a000a00010101
04040a000900010101
030108000a00010101
010007000a00010101
08040b000a00010101
0a030b000800010101
0c030b000600010101
0c050b000700010101
060403000800010101
030101000800010101
020304000800010101
070609000600010101
03030e000700010101
01050f000800010101
05010e000900010101
030009000800010101
01030c000800000101
01090e000800000101
030a08000a00010101
04020800000f000101
04090e00000f000100
030a08000004000101
07090c000600010001
07090c000f00000001
07090c000008010001
07090c000008000001
07090c030400010001
03020d00010a010100
00070c00000f010100
020b0e00010a010101
020b0e000006010101
020309000304010101
020309000004010101
03070e000102010100
05080a000002010100
000309030a00010101
00080d030800010101
020c0e030400010101
07090a000800010101
020809000600010101
010709000a00010101
00090a000a00010101
06070a000700010101
01010e000800010101
""".strip().splitlines()

def coefficients(code: int, section: int) -> tuple[int, int]:
    # Die-derived 4-bit setting and upstream 2026 measured capacitor law.
    k, c0, damping = ((0.00255, 3.38, 0.955),
                       (0.02837, 1.75, 0.935),
                       (0.03795, 4.07, 0.910))[section]
    capacitance = c0 + code   # binary 1/2/4/8 physical capacitor weights
    freq = FILTER_HZ / math.pi * math.asin(
        min(0.999, 0.5 * math.sqrt(k * capacitance)))
    freq = min(SAMPLE_HZ * 0.44, freq)
    angle = 2.0 * math.pi * freq / SAMPLE_HZ
    return (round(2.0 * damping * math.cos(angle) * 16384),
            round(damping * damping * 16384))

def generate() -> list[str]:
    assert len(DECODED) == 64
    out = []
    for line in DECODED:
        b = bytes.fromhex(line)
        assert len(b) == 9
        assert all(0 <= v <= 15 for v in b[:6])
        assert all(v in (0, 1) for v in b[6:])
        c, d = [], []
        for section in range(3):
            ci, di = coefficients(b[section], section)
            assert -32768 <= ci <= 32767 and 0 <= di <= 32767
            c.append(ci & 0xffff); d.append(di)
        # 128-bit packed word: c1/c2/c3, d1/d2/d3, metadata.
        # meta: VA:4 FA:4 b00:1 b01:1 b02:1 NAS:4
        meta = (b[4] << 28) | (b[5] << 24) | (b[6] << 23) | (
            b[7] << 22) | (b[8] << 21) | (b[3] << 16)
        fields = c + d + [(meta >> 16) & 0xffff, meta & 0xffff]
        out.append("".join(f"{v:04X}" for v in fields))
    return out

if __name__ == "__main__":
    data = generate()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(data) + "\n", encoding="ascii")
    print(f"Generated {len(data)} SSI-263 die-derived fixed-point formant words: {OUT}")
