#!/usr/bin/env python3
"""Rebuild P8 SSI263 silicon parameters and fixed-point five-section LUT.

Source: pinned MIT SSI263 C model in reference/ssi263/pico-v1.0.1.
No external download, no proprietary speech waveforms, no MAME samples.

ROM: 64 x 9 decoded 4-bit F1/F2/F3/NAS/VA/FA and 3 flags.
Coefficients: 3*16 capacitor-code biquads, plus fixed F4 and F5.
The five-section model uses the upstream normalized theta and bilinear
numerator gain, unlike P7's parallel unnormalized resonators.
"""
from pathlib import Path
import math
import re

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "reference/ssi263/pico-v1.0.1/ssi263_defaults.h"
OUT = ROOT / "boards/a2n20v2-Enhanced/hdl"
K = (0.00255, 0.02837, 0.03795)
C0 = (3.38, 1.75, 4.07)
BW = (0.0025, 0.004, 0.006, 0.03, 0.06)

def parameter_rows() -> list[str]:
    text = REF.read_text(encoding="utf-8")
    match = re.search(r"ssi263_default_rom_d\[576\]\s*=\s*\{(.*?)\};", text, re.S)
    if not match:
        raise RuntimeError("upstream 64x9 ROM missing")
    nums = [int(v) for v in re.findall(r"\b\d+\b", match.group(1))]
    assert len(nums) == 576
    rows = []
    for i in range(64):
        b = nums[i*9:i*9+9]
        assert len(b) == 9 and all(0 <= v <= 15 for v in b[:6])
        assert all(v in (0,1) for v in b[6:])
        packed = (b[0]<<28)|(b[1]<<24)|(b[2]<<20)|(b[3]<<16)|\
                 (b[4]<<12)|(b[5]<<8)|(b[6]<<2)|(b[7]<<1)|b[8]
        rows.append(f"{packed:08X}")
    return rows

def coefficient_rows() -> list[str]:
    rows=[]
    for i in range(50):
        if i < 48:
            section = i // 16
            code = i % 16
            # Silicon capacitor law: theta=2 asin(sqrt(K(C0+code))/2)
            theta=2*math.asin(min(.999, math.sqrt(K[section]*(C0[section]+code))/2))
        else:
            section = i-45
            theta=2*math.pi*(.163 if i==48 else .24)
        r=math.exp(-math.pi*BW[section])
        a1=2*r*math.cos(theta)
        a2=r*r
        g=(1-a1+a2)/4
        qa1=max(-32768,min(32767,round(a1*16384)))
        qa2=max(0,min(32767,round(a2*16384)))
        qg=max(0,min((1<<24)-1,round(g*(1<<24))))
        rows.append(f"{qa1&65535:04X}{qa2:04X}{qg:06X}")
    return rows

def glottal_rows() -> list[str]:
    """The MIT Pico C default has a 36-tick glottal wave, then 28 zeros."""
    text=REF.read_text(encoding="utf-8")
    match=re.search(
        r"ssi263_default_params_d\[SSI263_DEFAULT_PARAMS_N\]\s*=\s*\{(.*?)\};",
        text, re.S)
    if not match:
        raise RuntimeError("upstream chip parameter array missing")
    numbers=[float(v) for v in re.findall(r"(?<![A-Za-z])[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?",match.group(1))]
    # 100 numbers before glottal_wave (99: glottal_n=36).
    assert len(numbers)==166 and round(numbers[99])==36
    wave=numbers[100:136]
    assert len(wave)==36
    area=math.fsum(wave)
    assert abs(area-1.0)<1.e-9
    return [f"{round(x/area*32768)&65535:04X}" for x in (wave+[0.0]*28)]

def write_or_check(path: Path, rows: list[str], check: bool):
    contents="\n".join(rows)+"\n"
    if check:
        if path.read_text(encoding="ascii") != contents:
            raise RuntimeError(f"ROM drift: {path}")
        print(f"CHECK PASS: {len(rows)} words in {path}")
    else:
        path.write_text(contents,encoding="ascii")
        print(f"Wrote {len(rows)} words to {path}")

if __name__=="__main__":
    import argparse
    parser=argparse.ArgumentParser()
    parser.add_argument("--check",action="store_true")
    opts=parser.parse_args()
    write_or_check(OUT/"ssi263_p8_params.mem",parameter_rows(),opts.check)
    write_or_check(OUT/"ssi263_p8_coefs.mem",coefficient_rows(),opts.check)
    write_or_check(OUT/"ssi263_p8_glottal.mem",glottal_rows(),opts.check)
