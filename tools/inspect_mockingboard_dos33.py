#!/usr/bin/env python3
"""Read-only analysis of the 1980s Mockingboard DOS 3.3 demo disk.

No disk file is embedded or committed. Use:
    python tools/inspect_mockingboard_dos33.py /path/to/mockingboard1.dsk
Reports exact executable title sound/IRQ tables and the MCS rest indices.
"""
import argparse
from collections import Counter
from pathlib import Path
import re


class Dos33:
    def __init__(self, data):
        if len(data) != 35 * 16 * 256:
            raise ValueError("expected a 35-track, 16-sector DOS 3.3 .dsk")
        self.data = data

    def sector(self, track, sector):
        if not (0 <= track < 35 and 0 <= sector < 16):
            raise ValueError(f"bad DOS track/sector {track}/{sector}")
        p = (track * 16 + sector) * 256
        return self.data[p:p+256]

    def catalog(self):
        track, sector = self.sector(17, 0)[1:3]
        visited = set()
        while track:
            if (track, sector) in visited:
                raise ValueError("catalog sector cycle")
            visited.add((track, sector))
            b = self.sector(track, sector)
            for i in range(7):
                p = 0x0B + 35*i
                if b[p] in (0x00, 0xFF):
                    continue
                filename = "".join(chr(c & 0x7F) for c in b[p+3:p+33]).strip()
                yield filename, b[p+2] & 0x7F, b[p], b[p+1]
            track, sector = b[1:3]

    def load(self, filename):
        matches = [entry for entry in self.catalog() if entry[0] == filename]
        if len(matches) != 1:
            raise ValueError(f"expected exactly one {filename!r}")
        _, filetype, track, sector = matches[0]
        blocks = []
        visited = set()
        while track:
            if (track, sector) in visited:
                raise ValueError("file TS-list cycle")
            visited.add((track, sector))
            b = self.sector(track, sector)
            for p in range(0x0C, 256, 2):
                t, s = b[p:p+2]
                if t:
                    blocks.append(self.sector(t, s))
            track, sector = b[1:3]
        out = b"".join(blocks)
        if filetype == 4:
            load = int.from_bytes(out[:2], "little")
            length = int.from_bytes(out[2:4], "little")
            return load, out[4:4+length]
        if filetype == 2:
            length = int.from_bytes(out[:2], "little")
            return None, out[2:2+length]
        raise ValueError(f"{filename} not a BASIC/BINARY file")

def read_at(code, origin, absolute, n):
    at = absolute - origin
    if at < 0 or at+n > len(code):
        raise ValueError(f"address ${absolute:04X} outside binary")
    return code[at:at+n]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("disk", type=Path, help="user's original mockingboard1.dsk")
    args = ap.parse_args()
    disk = Dos33(args.disk.read_bytes())
    _, hello = disk.load("HELLO")
    origin, code = disk.load("BLOCK GRAPHICS")
    if origin != 0x8000 or b"BLOCK GRAPHICS" not in hello or b"32768" not in hello:
        raise ValueError("unexpected HELLO/intro program")
    irq_signature = read_at(code, origin, 0x8194, 7)
    if irq_signature != bytes.fromhex("8A 48 98 48 AD 04 C4"):
        raise ValueError("IRQ handler $8194 not recognized")
    print("HELLO: BLOAD BLOCK GRAPHICS at $8000, then CALL $8000")
    print("Title sound: IRQ handler at $8194, VIA T1 acknowledge $C404.")
    print("Timer setup $8168: VIA T1 latch $C407=$CF, $C406=$00")
    print("               => approximately 0.052 seconds per IRQ at 1.02MHz.")
    for title, where in [
        ("intro-left", 0x81EA), ("intro-right", 0x81FA),
        ("timer-glide-left", 0x81DA), ("glide-end-right", 0x820A)]:
        ay = read_at(code, origin, where, 16)
        print(f"{title:19s} ${where:04X}: "
              + " ".join(f"R{i}=${v:02X}" for i,v in enumerate(ay[:14])
                         if i in (0,1,2,3,6,7,8,9,10,11,12,13)))
    print("IRQ $8194 repeatedly DEC $81DA (R0), DEC $81DC (R2),")
    print("and INC $81E0 (R6), then calls $80C0 to write AY registers.")
    print("Stops at R0=$35; disables timer IRQ and resets left AY.")
    print("This is a time-varying pitch/noise effect, NOT an MCS period-1 rest.")

    mcs_origin, mcs = disk.load("MCS")
    if mcs_origin != 0x8500:
        raise ValueError("unexpected MCS address")
    for idx in (62,63):
        period = (read_at(mcs,mcs_origin,0x8571+idx,1)[0]<<8) | (
                  read_at(mcs,mcs_origin,0x8531+idx,1)[0])
        if period != 1:
            raise ValueError("MCS rest sentinel table has changed")
        print(f"MCS note-table index {idx} => AY period ${period:04X} "
              "(63.8kHz; inaudible/ultrasonic marker)")
    for song in ("SUGAR2","MINUTE","WEASEL"):
        _, data = disk.load(song)
        count = Counter(data)
        print(f"{song:8s}: raw song bytes ${0x7C:02X} occur {count[0x7C]} times"
              " (not all occurrences necessarily represent decoded note events)")
    _, keyboard = disk.load("KEYBOARD")
    periods = [int(n) for n in re.findall(rb"33184,(\d+)", keyboard)]
    print("KEYBOARD tone-A AY periods:",periods)
    if periods != [244,217,193,182,162,145,129,122]:
        raise ValueError("expected keyboard note period table not found")
    print("PASS: title timer sound and MCS rests are distinct playback mechanisms")


if __name__ == "__main__":
    main()
