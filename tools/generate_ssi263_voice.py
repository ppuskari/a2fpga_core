#!/usr/bin/env python3
"""Generate a small ORIGINAL approximation of the SSI-263 speech timbres.

No copyrighted chip ROM or sampled speech is required. 64 phoneme programs,
128 signed eight-bit PCM values per program, 8192 bytes total. This is an
approximate source-filter/formant timbre bank, NOT a transistor-accurate SSI263.
A free-running FPGA DDS controls actual pitch and the SSI bus handles duration.

Used by boards/a2n20v2-Enhanced/hdl/ssi263_voice.sv.
"""
from __future__ import annotations

import argparse
import hashlib
import math
from pathlib import Path

OUTPUT = (Path(__file__).resolve().parents[1] /
          "boards/a2n20v2-Enhanced/hdl/ssi263_voice.mem")
N = 128
SAMPLE_HZ = 16000
BASE_F0 = 125

# Phoneme names in physical SSI263 order, from MAME's BSD-3-clause
# ssi263hle.cpp/PHONEME_NAMES. Spectra below are original approximations.
NAMES = (
    "PA E E1 Y YI AY IE I A AI EH EH1 AE AE1 AH AH1 "
    "W O OU OO IU IU1 U U1 UH UH1 UH2 UH3 ER R R1 R2 "
    "L L1 LF W B D KV P T K HV HVC HF HFC HN Z S J SCH "
    "V F THV TH M N NG :A :OH :U :UH E2 LB"
).split()
assert len(NAMES) == 64

# Approximate English vowel formants in Hz, (F1 F2 F3).
# Phonetic mapping is a deliberate approximation; proprietary SSI tables
# are not available. This bank's job is recognizable triggers and vowels,
# with headroom to replace the timbres once compared with real silicon.
FORMANTS = {
    "front_high": (300, 2400, 3200),
    "front_mid":  (500, 2050, 2850),
    "front_low":  (700, 1700, 2600),
    "central":    (620, 1400, 2500),
    "low":        (760, 1150, 2550),
    "back_mid":   (520, 950, 2650),
    "back_high":  (350, 890, 2350),
    "r":          (480, 1200, 1700),
    "l":          (420, 1350, 2550),
    "nasal":      (260, 1150, 2150),
}
PHONEME_CLASS = {}
for group, words in {
    "front_high": "E E1 Y YI IE I IU IU1 E2",
    "front_mid": "AI EH EH1",
    "front_low": "AE AE1 AY",
    "central": "A AH AH1 UH UH1 UH2 UH3 :UH",
    "low": "O :A :OH",
    "back_mid": "OU OO",
    "back_high": "U U1 :U",
    "r": "ER R R1 R2",
    "l": "L L1 LF W",
    "nasal": "M N NG HN",
}.items():
    for name in words.split():
        PHONEME_CLASS[name] = group
for name in NAMES:
    PHONEME_CLASS.setdefault(name, "central")

# Consonants are rendered mainly from the FPGA's *non-looping* LFSR.
# Preserve a low-pitched voiced component for z/v/j/d/b etc.
UNVOICED = set("P T K HV HVC HF HFC S SCH F TH".split())
VOICED_FRICATIVES = set("Z J V THV".split())
PAUSES = {"PA", "LB"}

def harmonic(n: int, formants: tuple[int, int, int], soften: bool) -> float:
    t = 2 * math.pi * n / N
    out = 0.0
    for k in range(1, 27):
        frequency = k * BASE_F0
        f1, f2, f3 = formants
        # Broad resonances approximate oral tract shape.
        env = (
            0.04
            + 1.5 * math.exp(-0.5 * ((frequency - f1) / 170.0) ** 2)
            + 1.1 * math.exp(-0.5 * ((frequency - f2) / 280.0) ** 2)
            + 0.50 * math.exp(-0.5 * ((frequency - f3) / 360.0) ** 2)
        )
        if soften:
            env *= 0.35
        out += env * math.sin(t * k) / math.sqrt(k)
    return out

def generate():
    frames: list[int] = []
    for idx, name in enumerate(NAMES):
        f = FORMANTS[PHONEME_CLASS[name]]
        waves = [harmonic(n, f, name in UNVOICED) for n in range(N)]
        peak = max(1e-9, max(abs(x) for x in waves))
        # 80-90 samples of peak leaves substantial headroom for amplitude.
        gain = 0.0 if name in PAUSES else (
            0.25 if name in UNVOICED else
            0.65 if name in VOICED_FRICATIVES else 1.0)
        for v in waves:
            sample = round(94.0 * gain * v / peak)
            frames.append(max(-127, min(127, sample)) & 0xff)
    assert len(frames) == 8192
    return bytes(frames)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=OUTPUT)
    parser.add_argument("--check", action="store_true",
                        help="verify an already-generated ROM without changing it")
    args = parser.parse_args()
    data = generate()
    rom = "".join(f"{v:02X}\n" for v in data)
    if args.check:
        if not args.out.exists() or args.out.read_text(encoding="ascii") != rom:
            raise SystemExit("SSI voice ROM missing or stale; regenerate it")
    else:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(rom, encoding="ascii")
    print("SSI263 original formant approximation: "
          f"{len(data)} signed PCM bytes, 64 x 128, "
          f"SHA256={hashlib.sha256(data).hexdigest()}")
    print(f"ROM: {args.out}")

if __name__ == "__main__":
    main()
