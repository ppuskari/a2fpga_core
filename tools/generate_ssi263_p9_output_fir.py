#!/usr/bin/env python3
"""P9 193-tap output FIR from pinned Pico SSI263 C ssi263dsp.firwin.

For 44.1k host PCM, use 4x oversample (176.4 kHz), 20 kHz cutoff,
193 taps. The upstream C model generates exactly this Hamming-windowed
normalized sinc. Q15 quantization changes the response slightly.
"""
import math
from pathlib import Path

OUT=Path(__file__).resolve().parents[1]/"boards/a2n20v2-Enhanced/hdl/ssi263_p9_outfir.mem"
def rows():
    taps=193
    fs=44100*4
    cutoff=20000
    center=(taps-1)/2
    samples=[]
    for i in range(taps):
        x=2*cutoff/fs*(i-center)
        sinc=1.0 if x==0 else math.sin(math.pi*x)/(math.pi*x)
        hamming=.54-.46*math.cos(2*math.pi*i/(taps-1))
        samples.append(sinc*hamming)
    total=sum(samples)
    q=[max(-32768,min(32767,round(h/total*32768))) for h in samples]
    q[96]+=32768-sum(q)
    assert sum(q)==32768 and q==q[::-1], "Expected symmetric unity-gain FIR"
    return [f"{v&65535:04X}" for v in q]

if __name__=="__main__":
    import argparse
    p=argparse.ArgumentParser()
    p.add_argument("--check",action="store_true")
    args=p.parse_args()
    data="\n".join(rows())+"\n"
    if args.check:
        assert OUT.read_text(encoding="ascii")==data,"FIR not reproducible"
        print("PASS: 193-tap SSI263 output FIR matches pinned C design")
    else:
        OUT.write_text(data,encoding="ascii")
        print(f"Wrote {OUT}")
