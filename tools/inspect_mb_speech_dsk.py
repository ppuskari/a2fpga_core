#!/usr/bin/env python3
"""Read-only SSI263 playback map for Mockingboard Demo Disk 1 DOS 3.3 .dsk.

Usage: python tools/inspect_mb_speech_dsk.py /path/to/mockingboard1.dsk
The source DOS disk is not copied or distributed in this repository.
"""
import argparse
from pathlib import Path

def sector(disk, track, sector):
    if not (0 <= track < 35 and 0 <= sector < 16):
        raise ValueError("Invalid DOS sector")
    p = (track * 16 + sector) * 256
    return disk[p:p+256]

def catalog(disk):
    track, sn = sector(disk, 17, 0)[1:3]
    visited = set()
    while track:
        if (track, sn) in visited:
            raise ValueError("Catalog cycle")
        visited.add((track, sn))
        data = sector(disk, track, sn)
        for i in range(7):
            j = 11 + 35 * i
            if data[j] in (0,255):
                continue
            name = "".join(chr(c & 127) for c in data[j+3:j+33]).strip()
            yield name, data[j+2] & 127, data[j], data[j+1]
        track, sn = data[1:3]

def load(disk, name):
    found = [x for x in catalog(disk) if x[0] == name]
    if len(found) != 1:
        raise ValueError("Missing or repeated DOS item: " + name)
    _, file_type, track, sn = found[0]
    chunks, seen = [], set()
    while track:
        if (track, sn) in seen:
            raise ValueError("DOS track/sector list cycle")
        seen.add((track, sn))
        ts = sector(disk, track, sn)
        for j in range(12, 256, 2):
            t, s = ts[j:j+2]
            if t: chunks.append(sector(disk, t, s))
        track, sn = ts[1:3]
    raw = b"".join(chunks)
    if file_type == 4:
        base, length = int.from_bytes(raw[:2], "little"), int.from_bytes(raw[2:4],"little")
        return base, raw[4:4+length]
    if file_type == 2:
        length = int.from_bytes(raw[:2],"little")
        return None, raw[2:2+length]
    raise ValueError("Unsupported DOS file type")

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("disk", type=Path)
    args = ap.parse_args()
    disk = args.disk.read_bytes()
    if len(disk) != 143360:
        raise SystemExit("Expected uncompressed DOS 3.3 143,360-byte .dsk")
    base, driver = load(disk,"COMPOSITE DRIVER")
    msgbase, messages = load(disk,"MESS")
    _, demo = load(disk,"SPEECH DEMO")
    if (base,msgbase) != (0x6d00,0x5000) or b"MESS" not in demo:
        raise SystemExit("Not the expected Demo Disk 1")
    signatures = [
        ("right VIA CA1 IER enable", "A9 82 8D 8E C4"),
        ("right VIA CA1 IFR acknowledge", "A9 02 8D 8D C4"),
        ("SSI standby", "A9 80 8D 43 C4"),
        ("SSI phoneme mode", "A9 C0 8D 40 C4"),
        ("SSI power-up", "A9 70 8D 43 C4"),
        ("SSI register stream", "9D 40 C4")
    ]
    for label, source in signatures:
        at = driver.find(bytes.fromhex(source))
        if at < 0:
            raise SystemExit("Missing signature: " + label)
        print("%04X  %s" % (base+at,label))
    for page in [0,0x300,0x500,0x700,0xa00,0xb00,0xf00,0x1000,0x1200,0x1300]:
        if page+2 > len(messages):
            continue
        n = int.from_bytes(messages[page:page+2],"little")
        if n<2 or (n-2)%5 or page+n>len(messages):
            continue
        print("MESSAGE %04X: %d phonemes" % (msgbase+page,(n-2)//5))
        if page==0:
            if messages[2:12] != bytes.fromhex("E8 7F A8 6F 60 E8 6E A8 63 88"):
                raise SystemExit("First MESS phonemes changed")
            for j in range(min(12,(n-2)//5)):
                rec = messages[page+2+j*5:page+7+j*5]
                print("  %02d R4..R0=%s phoneme=%02X" %
                      (j,rec.hex(" "),rec[4]&63))
    print("PASS: genuine Demo Disk 1 SSI driver and phoneme data identified")

if __name__ == "__main__":
    main()
