#!/usr/bin/env python3
"""DOC5503 one-shot FX bank builder. Audio preload/triggering is NOT yet integrated.

Accept user-owned PCM WAV samples or synthesize explicitly marked diagnostic
fixtures. No external dependencies. All tables reserve the last byte ($00)
as the DOC HALT marker; earlier PCM bytes may never contain $00.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import wave

RATE = 16000  # source reference only; actual DOC playback rate is FC-dependent
BASE = 0x2000
END = 0x7000  # 20KiB reserved region, below first 64KiB; piano below 0x1600
SLOTS = (
    ("explosion", 0x2000, 8192),
    ("kick",      0x4000, 1024),
    ("snare",     0x4400, 1024),
    ("tom",       0x4800, 1024),
    ("hihat",     0x4C00, 1024),
    ("laser",     0x5000, 2048),
    ("cymbal",    0x6000, 4096),
)

def fixture(name, n):
    """Synthetic testing signals. NOT production-quality samples."""
    state = 0xBEEF ^ sum(map(ord, name))
    smooth = 0.0
    phase = 0.0
    result = []
    for i in range(n):
        t = i/RATE
        u = i/max(n-1, 1)
        bit = (state ^ (state>>2) ^ (state>>3) ^ (state>>5)) & 1
        state = ((state>>1)|(bit<<15))&65535
        noise = 1.0 if state&1 else -1.0
        smooth = 0.84*smooth+0.16*noise
        if name=="explosion":
            val = (0.6*smooth+0.3*noise*math.exp(-45*t))*math.exp(-5.0*u)
        elif name=="kick":
            phase += 2*math.pi*(52+105*math.exp(-27*t))/RATE
            val = 0.88*math.sin(phase)*math.exp(-24*t)
        elif name=="snare":
            val = (0.63*noise+0.2*math.sin(2*math.pi*175*t))*math.exp(-26*t)
        elif name=="tom":
            phase += 2*math.pi*(85+65*math.exp(-15*t))/RATE
            val = 0.8*math.sin(phase)*math.exp(-14*t)
        elif name=="hihat":
            val = 0.5*(noise-smooth)*math.exp(-46*t)
        elif name=="laser":
            phase += 2*math.pi*(160+1200*(1-u)**2)/RATE
            val = 0.66*math.sin(phase)*(1-u)
        elif name=="cymbal":
            val = 0.53*(noise-0.62*smooth)*math.exp(-4.5*u)
        else:
            raise ValueError(name)
        result.append(max(-0.99,min(0.99,val)))
    return result

def read_wav(path):
    with wave.open(str(path),"rb") as w:
        nch, width, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
        if nch not in (1,2) or width not in (1,2) or rate<1 or w.getcomptype()!="NONE":
            raise ValueError("Only uncompressed mono/stereo 8/16-bit PCM WAV supported: "+str(path))
        frames=w.getnframes()
        raw=w.readframes(frames)
    vals=[(x-128)/128 for x in raw] if width==1 else [
        x/32768 for x in struct.unpack("<%dh"%(len(raw)//2),raw)]
    signal=[sum(vals[nch*i:nch*(i+1)])/nch for i in range(frames)]
    if not signal:
        raise ValueError("Empty sample: "+str(path))
    count=max(1,round(len(signal)*RATE/rate))
    converted=[]
    for i in range(count):
        pos=i*rate/RATE
        a=min(int(pos),len(signal)-1)
        b=min(a+1,len(signal)-1)
        f=max(0.0,min(1.0,pos-a))
        converted.append(signal[a]*(1-f)+signal[b]*f)
    return converted

def pack(samples,length):
    if len(samples)>length-1:
        raise ValueError("Sample too long: %d source frames, %d maximum"%(len(samples),length-1))
    pcm=bytearray([128]*length)
    for i,x in enumerate(samples):
        pcm[i]=max(1,min(255,round(128+127*x)))
    pcm[-1]=0
    assert 0 not in pcm[:-1]
    return bytes(pcm)

def build(out,input_dir=None,fixtures=False):
    if fixtures == (input_dir is not None):
        raise ValueError("Specify exactly one of --fixtures and --input-dir")
    out.mkdir(parents=True,exist_ok=True)
    bank=bytearray([128]*(END-BASE))
    metadata=[]
    prev=BASE
    for name,addr,length in SLOTS:
        assert addr >= prev and addr%length==0 and addr+length<=END
        assert length>=256 and length&(length-1)==0
        samples=fixture(name,length-1) if fixtures else read_wav(input_dir/(name+".wav"))
        table=pack(samples,length)
        wts=(length.bit_length()-1)-8
        assert 256<<wts==length
        bank[addr-BASE:addr+length-BASE]=table
        metadata.append({"name":name,"start":addr,"wtp":addr//256,"wts":wts,
            "bytes":length,"source_frames":len(samples),"terminal_zero_at":length-1,
            "sha256":hashlib.sha256(table).hexdigest(),
            "status":"DIAGNOSTIC ONLY" if fixtures else "USER WAV / LISTENING UNVERIFIED"})
        prev=addr+length
        if fixtures:
            # Replace DOC HALT byte with silence for conventional WAV audition.
            with wave.open(str(out/(name+"_test.wav")),"wb") as w:
                w.setnchannels(1);w.setsampwidth(1);w.setframerate(RATE)
                w.writeframes(table[:-1]+bytes([128]))
    blob=bytes(bank)
    (out/"mb_fx_bank.bin").write_bytes(blob)
    (out/"mb_fx_bank.mem").write_text("".join(
        "%08X\n"%int.from_bytes(blob[i:i+4],"little")
        for i in range(0,len(blob),4)))
    manifest={"format":"8-bit offset-binary DOC5503 one-shot, terminal zero HALT",
        "region_start":BASE,"region_end_exclusive":END,"base_ram_word":BASE//4,
        "reference_sample_rate_hz":RATE,"notes":"PRELOAD/FX OSCILLATORS NOT YET INTEGRATED",
        "source":"TEST FIXTURES" if fixtures else "USER SUPPLIED WAV",
        "bank_sha256":hashlib.sha256(blob).hexdigest(),"patches":metadata}
    (out/"mb_fx_bank.json").write_text(json.dumps(manifest,indent=2)+"\n")
    print("PASS FX bank: %d bytes, %d patches, fixtures=%s, preload not integrated"%
          (len(blob),len(SLOTS),fixtures))
    return manifest

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    group=ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--fixtures",action="store_true")
    group.add_argument("--input-dir",type=Path)
    ap.add_argument("--out",type=Path,required=True)
    args=ap.parse_args()
    bank=build(args.out,args.input_dir,args.fixtures)
    for patch in bank["patches"] if False else bank:
        print("%s: WTP=%02X WTS=%d bytes=%d"%
              (patch["name"],patch["wtp"],patch["wts"],patch["bytes"]))
if __name__=="__main__":
    main()
