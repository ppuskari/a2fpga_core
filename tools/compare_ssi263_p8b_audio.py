#!/usr/bin/env python3
"""A/B reference audit for exact SSI-263 1MHz command trace.

Inputs are raw PCM16-LE at 50 kHz from pinned Pico C and P8B SystemVerilog.
Do NOT infer acoustic fidelity from a nonzero simulation or C compile pass.
Report level, intersample discontinuities, band powers and lagged correlation.
Exit status is zero for a *completed audit*, not a passing fidelity gate.
"""
from __future__ import annotations
import argparse, json, math, struct
from pathlib import Path

def load(path:Path)->list[float]:
    b=path.read_bytes()
    assert len(b)==15000, f"{path}: expected 7,500 mono PCM16 samples, got {len(b)//2}"
    return [float(v) for v in struct.unpack("<7500h",b)]

def rms(x):
    return math.sqrt(sum(v*v for v in x)/max(1,len(x)))
def db(v):
    return 20*math.log10(max(v,1.e-10)/32768)
def power_bands(x,sr=50000):
    # Welch-like spectral power from nonoverlapping 512-sample blocks.
    import numpy as np
    signal=np.asarray(x,dtype=np.float64)
    blocks=np.stack([signal[i:i+512] for i in range(0,len(x)-512,512)])
    blocks*=np.hanning(512)
    p=(abs(np.fft.rfft(blocks,axis=1))**2).mean(axis=0)
    f=np.fft.rfftfreq(512,d=1/sr)
    bounds=[(80,400),(400,1400),(1400,3500),(3500,7500),(7500,14000),(14000,25000)]
    results=[]
    for lo,hi in bounds:
        results.append(float(p[(f>=lo)&(f<hi)].sum()))
    return results

def similarity(a,b):
    import numpy as np
    aa=np.asarray(a,dtype=float);bb=np.asarray(b,dtype=float)
    # Lag scan +/- 10 ms, remove mean and normalize at each position.
    z=[]
    for lag in range(-500,501,5):
        if lag<0: x,y=aa[-lag:],bb[:lag]
        elif lag>0: x,y=aa[:-lag],bb[lag:]
        else: x,y=aa,bb
        if len(x)==0:continue
        x=x-x.mean();y=y-y.mean()
        den=np.linalg.norm(x)*np.linalg.norm(y)
        z.append((float(np.dot(x,y)/den) if den else 0.,lag))
    return max(z,key=lambda it:abs(it[0]))

def analyze(x):
    a=max(abs(v) for v in x)
    jumps=[abs(x[i]-x[i-1]) for i in range(1,len(x))]
    bands=power_bands(x)
    total=sum(bands)
    return {"peak_dbfs":round(db(a),2),
            "rms_dbfs":round(db(rms(x)),2),
            "largest_pcm_step":int(max(jumps)),
            "clip_fraction":round(sum(abs(v)>=32767 for v in x)/len(x),6),
            "band_power_pct":[round(100*v/max(total,1.e-10),2) for v in bands]}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("reference",type=Path)
    p.add_argument("rtl",type=Path)
    p.add_argument("--report",type=Path,default=Path("p8b_comparison.json"))
    args=p.parse_args()
    r=load(args.reference);v=load(args.rtl)
    ref=analyze(r);rtl=analyze(v)
    corr,lag=similarity(r,v)
    result={"reference":ref,"rtl":rtl,
       "peak_difference_db":round(rtl["peak_dbfs"]-ref["peak_dbfs"],2),
       "rms_difference_db":round(rtl["rms_dbfs"]-ref["rms_dbfs"],2),
       "max_lagged_correlation":round(corr,4),
       "best_lag_samples":lag,
       "fidelity_accepted":False,
       "acceptance_note":"Not accepted until RMS, pitch, formant, timing, and waveform correlation gates are defined and passed"}
    args.report.write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps(result,indent=2))
    assert rtl["clip_fraction"]<0.05,"Excessive hard clipping: invalidate RTL build"
    assert rtl["peak_dbfs"]>-100,"P8B voice is silent"
    print("AUDIT GENERATED; waveform fidelity NOT established")

if __name__=="__main__":main()
