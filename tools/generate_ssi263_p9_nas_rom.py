#!/usr/bin/env python3
"""P9: derive F2 biquad coefficients for every die F2 and NAS setting.

Derived directly from the pinned Pico C model's capacitor and damping law:
set_theta(F2, 2asin(sqrt(K*(C0+F2))/2),
          BW2 * (1 + nas_f2_bw_gain * NAS)).
Each 56-bit coefficient word: a1 (Q14 signed), a2 (Q14 signed),
and bilinear numerator g (Q24 positive).
"""
import math
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"boards/a2n20v2-Enhanced/hdl/ssi263_p9_f2nas.mem"

def rows():
    result=[]
    for nas in range(16):
        for f2 in range(16):
            theta=2*math.asin(min(.999,math.sqrt(.02837*(1.75+f2))/2))
            bw=.004*(1+.5*nas)
            r=math.exp(-math.pi*bw)
            a1=2*r*math.cos(theta)
            a2=r*r
            g=(1-a1+a2)/4.0
            q1=max(-32768,min(32767,round(a1*16384)))&65535
            q2=max(0,min(32767,round(a2*16384)))
            qg=max(0,min((1<<24)-1,round(g*(1<<24))))
            result.append(f"{q1:04X}{q2:04X}{qg:06X}")
    assert len(result)==256
    return result

if __name__=="__main__":
    import argparse
    p=argparse.ArgumentParser()
    p.add_argument("--check",action="store_true")
    o=p.parse_args()
    data="\n".join(rows())+"\n"
    if o.check:
        assert OUT.read_text(encoding="ascii")==data,"F2/NAS ROM drift from pinned Pico model"
        print("PASS 256 die F2/NAS coefficient pairs")
    else:
        OUT.write_text(data,encoding="ascii")
        print("Generated",OUT)
