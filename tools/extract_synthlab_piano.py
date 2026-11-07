#!/usr/bin/env python3
"""Extract all seven authentic SynthLAB piano sustains into a Gowin ROM .mem.

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
SAMPLE_FNV = 0x170BB8B3  # FNV of the complete packed 5632-byte ROM
# Original SynthLAB wave-definition indexes; packed into consecutive DOC pages.
# These are SUSTAIN waves only. The 8KB hammer attacks are not looped.
SUSTAIN_WAVES = [
    (1, "~Piano C1", 0x1400, 2, 0x522BF29E),
    (3, "~Piano G1", 0x1000, 2, 0x36D4FEED),
    (5, "~Piano E2", 0x0400, 2, 0x258A0E23),
    (7, "~Piano C3", 0x1800, 2, 0x430E4B0A),
    (9, "~Piano B3", 0x1C00, 1, 0xA0AF32B8),
    (11, "~Piano F4", 0x1E00, 1, 0xD8ED309B),
    (13, "~Piano D5", 0x0800, 1, 0xA202699A),
]
DEFAULT_OUTPUT = (Path(__file__).resolve().parents[1]
                  / "boards/a2n20v2-Enhanced/hdl/piano_multisustain.mem")


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
    if bank_offset != 0x900 or valid_waves < 14:
        raise ValueError("Unexpected SynthLAB Wave header")
    packed = bytearray()
    for index, expected_name, expected_addr, expected_size, expected_hash in SUSTAIN_WAVES:
        entry = wavefile[0x100 + index * 32:0x100 + (index + 1) * 32]
        name = entry[1:1 + entry[0]].decode("ascii")
        address = u16(entry, 16)
        size_code = entry[19]
        if (name, address, size_code) != (expected_name, expected_addr, expected_size):
            raise ValueError(f"Unexpected wave {index}: {name}, address={address:x}, size={size_code}")
        length = 256 << size_code
        pcm = wavefile[bank_offset + address:bank_offset + address + length]
        if len(pcm) != length or 0 in pcm:
            raise ValueError(f"Invalid DOC PCM for {name}")
        if fnv32(pcm) != expected_hash:
            raise ValueError(f"Wrong PCM checksum for {name}: {fnv32(pcm):08X}")
        packed.extend(pcm)
    if len(packed) != 5632 or fnv32(packed) != SAMPLE_FNV:
        raise ValueError(f"Wrong packed sustain checksum {fnv32(packed):08X}")
    return bytes(packed)

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
    print("Verified seven Apple SynthLAB sustain zones; 5632 bytes, 1408 words, "
          "packed FNV32=170BB8B3, no DOC stop bytes.")
    print(f"Generated: {opts.out.resolve()}")
    print("Do not commit the generated Apple PCM waveform file.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        sys.exit(f"ERROR: {error}")
