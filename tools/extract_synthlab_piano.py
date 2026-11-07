#!/usr/bin/env python3
"""Extract authentic 1024-byte SynthLAB ~Piano C3 sustain into a Gowin ROM .mem.

Requires the original Apple IIgs System 6.0.4 SynthLAB ProDOS-order disk image.
--download fetches it from a public archive; --disk accepts a local image.
Apple PCM stays a generated local asset; it is not distributed in this repo.
"""
import argparse
import hashlib
from pathlib import Path
import struct
import sys
import urllib.request

DISK_URL = ("https://raw.githubusercontent.com/gungwald/apple-ii-dev/main/"
            "var/apple2gs/Apple_IIGS_System_6.0.4/PO%20Disk%20Images/synthLAB.po")
DISK_MD5 = "fa4f143dd899d0cc4c8ed9c9e41b7d37"
SAMPLE_FNV = 0x430E4B0A
DEFAULT_OUTPUT = (Path(__file__).resolve().parents[1]
                  / "boards/a2n20v2-Enhanced/hdl/piano_c3_sustain.mem")


def u16(buf, off):
    return struct.unpack_from("<H", buf, off)[0]


def find_entry(disk, first_block, desired):
    block = first_block
    visited = set()
    while block:
        if block in visited or block * 512 + 512 > len(disk):
            raise ValueError("Bad ProDOS directory block chain")
        visited.add(block)
        offset = block * 512
        next_block = u16(disk, offset + 2)
        for i in range(13):
            at = offset + 4 + 39 * i
            type_nibble = disk[at] >> 4
            count = disk[at] & 15
            if type_nibble in (0, 14, 15) or not count:
                continue
            name = disk[at + 1:at + 1 + count].decode("ascii")
            if name.casefold() == desired.casefold():
                eof = int.from_bytes(disk[at + 21:at + 24], "little")
                return type_nibble, u16(disk, at + 17), eof, disk[at + 16]
        block = next_block
    raise ValueError(f"ProDOS item not found: {desired}")


def read_sapling(disk, index_block, eof):
    if eof > 128 * 1024:
        raise ValueError("ProDOS sapling size out of bounds")
    index = disk[index_block * 512:(index_block + 1) * 512]
    if len(index) != 512:
        raise ValueError("Bad ProDOS sapling index block")
    data = bytearray()
    for i in range((eof + 511) // 512):
        block = index[i] | (index[256 + i] << 8)
        if not block:
            data.extend(bytes(512))
        else:
            fragment = disk[block * 512:(block + 1) * 512]
            if len(fragment) != 512:
                raise ValueError("Truncated ProDOS data block")
            data.extend(fragment)
    return bytes(data[:eof])


def fnv32(data):
    h = 0x811C9DC5
    for b in data:
        h = ((h ^ b) * 0x01000193) & 0xffffffff
    return h


def extract(disk):
    if len(disk) != 819200:
        raise ValueError("Disk must be an 800K ProDOS-order .po image")
    md5 = hashlib.md5(disk).hexdigest()
    if md5 != DISK_MD5:
        raise ValueError(f"Wrong disk MD5 {md5}; expected {DISK_MD5}")
    folder_type, folder, _, _ = find_entry(disk, 2, "SEQ.AND.INSTR")
    if folder_type != 0xD:
        raise ValueError("SEQ.AND.INSTR is not a directory")
    storage, index, length, ftype = find_entry(disk, folder, "PIANO.WAV")
    if (storage, length, ftype) != (2, 0x10900, 0xD8):
        raise ValueError("Unexpected ProDOS PIANO.WAV metadata")
    wavefile = read_sapling(disk, index, length)
    if wavefile[:4] != b"WAVE" or u16(wavefile, 4) != 0x100:
        raise ValueError("Not a version 1 Apple MIDI Synth Wave file")
    bank_offset = u16(wavefile, 6)
    valid_waves = u16(wavefile, 0x18)
    if bank_offset != 0x900 or valid_waves < 8:
        raise ValueError("Unexpected SynthLAB Wave header")
    entry = wavefile[0x100 + 7 * 32:0x100 + 8 * 32]
    name = entry[1:1 + entry[0]].decode("ascii")
    address = u16(entry, 16)
    size_code = entry[19]
    if (name, address, size_code) != ("~Piano C3", 0x1800, 2):
        raise ValueError(f"Unexpected wave definition {name}, address={address}, size={size_code}")
    pcm = wavefile[bank_offset + address:bank_offset + address + 1024]
    if len(pcm) != 1024 or 0 in pcm:
        raise ValueError("Invalid sample length or forbidden DOC zero byte")
    hash32 = fnv32(pcm)
    if hash32 != SAMPLE_FNV:
        raise ValueError(f"Unexpected Piano C3 PCM hash {hash32:08X}")
    return pcm


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    source = ap.add_mutually_exclusive_group(required=True)
    source.add_argument("--disk", type=Path)
    source.add_argument("--download", action="store_true")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUTPUT)
    opts = ap.parse_args()
    if opts.download:
        with urllib.request.urlopen(DISK_URL, timeout=45) as response:
            disk = response.read()
    else:
        disk = opts.disk.read_bytes()
    pcm = extract(disk)
    opts.out.parent.mkdir(parents=True, exist_ok=True)
    opts.out.write_text("".join(f"{int.from_bytes(pcm[i:i+4], 'little'):08X}\n"
                                for i in range(0, len(pcm), 4)), encoding="ascii")
    print("Verified Apple SynthLAB Piano C3; 1024 bytes, 256 words, "
          "DOC size=1K, FNV32=430E4B0A, no zero samples.")
    print(f"Generated: {opts.out.resolve()}")
    print("Do not commit the generated Apple PCM waveform file.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        sys.exit(f"ERROR: {error}")
