#!/usr/bin/env python3
"""Verify deterministic diagnostic FX bank and DOC one-shot stop semantics."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import wave

ROOT=Path(__file__).resolve().parents[2]
BUILDER=ROOT/"tools/build_mb_doc_fx_bank.py"

def generate(directory):
    subprocess.run([sys.executable,str(BUILDER),"--fixtures","--out",str(directory)],
                   check=True,cwd=ROOT)
    m=json.loads((directory/"mb_fx_bank.json").read_text())
    b=(directory/"mb_fx_bank.bin").read_bytes()
    lines=(directory/"mb_fx_bank.mem").read_text().splitlines()
    assert len(b)==0x5000 and len(lines)==len(b)//4
    assert b==b"".join(int(s,16).to_bytes(4,"little") for s in lines)
    assert hashlib.sha256(b).hexdigest()==m["bank_sha256"]
    assert m["source"]=="TEST FIXTURES"
    assert m["region_start"]==0x2000 and m["region_end_exclusive"]==0x7000
    assert len(m["patches"])==7
    for p in m["patches"]:
        addr=p["start"]-0x2000
        length=p["bytes"]
        assert addr>=0 and addr+length<=len(b) and p["wtp"]==p["start"]//256
        assert 256 << p["wts"] == length
        assert p["start"] % length==0
        sample=b[addr:addr+length]
        assert sample[-1]==0 and 0 not in sample[:-1],(p["name"],"premature DOC HALT")
        assert hashlib.sha256(sample).hexdigest()==p["sha256"]
        assert p["status"]=="DIAGNOSTIC ONLY"
        with wave.open(str(directory/(p["name"]+"_test.wav")),"rb") as w:
            assert (w.getframerate(),w.getnchannels(),w.getsampwidth(),w.getnframes())==(16000,1,1,length)
            assert w.readframes(length)==sample[:-1]+bytes([128])
    # No overlap with the verified original SynthLAB piano 0x0000..0x15FF.
    assert m["region_start"]>=0x1600
    return b,m

def main():
    with tempfile.TemporaryDirectory(prefix="mbfx-test-") as a, tempfile.TemporaryDirectory(prefix="mbfx-test-") as b:
        p,_=generate(Path(a))
        q,_=generate(Path(b))
        assert p==q,"diagnostic PCM generation must be reproducible"
    print("PASS: seven sample-bank slots, 20KiB memory image, WTP/WTS, HALT, PCM hashes, deterministic build")

if __name__=="__main__":
    main()
