#!/usr/bin/env python3
"""Prepare/check the complete Enhanced Tang Nano 20K FPGA ROM inventory.

No manual ROM extraction: the original, redistribution-safe SSI263 banks are
tracked in Git; this verifies them against deterministic local generators.

Apple's SynthLAB sample bytes are a separate third-party work, so the exact
piano sustain ROM is derived on the developer's computer from the publicly
accessible, pinned synthLAB.po or a user-supplied offline disk image. It is
verified before any Gowin synthesis. No fake/zero piano samples are substituted.

Examples:
  python tools/prepare_enhanced_assets.py
  python tools/prepare_enhanced_assets.py --check
  python tools/prepare_enhanced_assets.py --disk C:/images/synthLAB.po
  python tools/prepare_enhanced_assets.py --offline
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
HDL = ROOT / "boards/a2n20v2-Enhanced/hdl"
EXTRACT = ROOT / "tools/extract_synthlab_piano.py"
PIANO = HDL / "piano_multisustain.mem"
ROM_CHECKS = (
    ("ssi263_voice.mem", "generate_ssi263_voice.py"),
    ("ssi263_p8_params.mem", "generate_ssi263_p8_roms.py"),
    ("ssi263_p8_coefs.mem", "generate_ssi263_p8_roms.py"),
    ("ssi263_p8_glottal.mem", "generate_ssi263_p8_roms.py"),
    ("ssi263_p9_f2nas.mem", "generate_ssi263_p9_nas_rom.py"),
    ("ssi263_p9_outfir.mem", "generate_ssi263_p9_output_fir.py"),
)


def invoke(tool: str, *args: object) -> None:
    command = [sys.executable, str(ROOT / "tools" / tool), *(str(a) for a in args)]
    cp = subprocess.run(command, cwd=ROOT, check=False)
    if cp.returncode:
        raise RuntimeError(f"ROM preparation failed: {tool} {' '.join(map(str, args))}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="verify all existing ROMs without generating/downloading anything")
    ap.add_argument("--offline", action="store_true",
                    help="use previously extracted piano or --disk, never access network")
    ap.add_argument("--disk", type=Path,
                    help="local original 800KiB ProDOS-order synthLAB.po")
    opts = ap.parse_args()

    # Generate/check once per tool: P8 generates three .mem files at once.
    tools = dict.fromkeys(tool for _, tool in ROM_CHECKS)
    for tool in tools:
        paths = [HDL / name for name, source in ROM_CHECKS if source == tool]
        if all(path.is_file() for path in paths):
            invoke(tool, "--check")
        else:
            if opts.check:
                missing = ", ".join(str(path) for path in paths if not path.exists())
                raise RuntimeError("Missing SSI263 ROM(s): " + missing)
            invoke(tool)
            invoke(tool, "--check")

    disk = opts.disk
    if disk is None:
        configured = os.environ.get("A2FPGA_SYNTHLAB_DISK", "").strip()
        disk = Path(configured) if configured else None

    if PIANO.is_file():
        try:
            invoke("extract_synthlab_piano.py", "--check", "--out", PIANO)
        except RuntimeError as exc:
            if opts.check or opts.offline and disk is None:
                raise
            print("Existing SynthLAB ROM failed verification: will re-extract"
                  " from an authenticated source", file=sys.stderr)
            PIANO.unlink()
    elif opts.check:
        raise RuntimeError(
            f"Missing {PIANO}; run python tools/prepare_enhanced_assets.py "
            "or supply --disk to prepare an offline build."
        )

    if not PIANO.is_file():
        if disk is not None:
            if not disk.is_file():
                raise RuntimeError(f"SynthLAB source disk not found: {disk}")
            invoke("extract_synthlab_piano.py", "--disk", disk, "--out", PIANO)
        elif opts.offline:
            raise RuntimeError(
                f"Offline piano ROM missing: {PIANO}\n"
                "Set A2FPGA_SYNTHLAB_DISK to your synthLAB.po image, or pass "
                "--disk /path/to/synthLAB.po; run once to populate local cache."
            )
        else:
            invoke("extract_synthlab_piano.py", "--download", "--out", PIANO)
        invoke("extract_synthlab_piano.py", "--check", "--out", PIANO)

    if not PIANO.is_file():
        raise RuntimeError("Piano ROM missing after preparation; aborting FPGA build")
    print("PASS ENHANCED: tracked SSI263 ROMs verified and authentic "
          "7-zone SynthLAB piano ROM prepared")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError) as exc:
        sys.exit("ERROR: " + str(exc))
