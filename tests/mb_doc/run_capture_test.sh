#!/usr/bin/env sh
# Self-contained AY bus event test. Requires Icarus Verilog.
# The capture module is embedded in mockingboard.sv; the test
# define excludes only the full card (which has VHDL dependencies).
set -eu
cd "$(dirname "$0")/../.."
command -v iverilog >/dev/null 2>&1 || {
  echo "ERROR: install Icarus Verilog (iverilog and vvp)." >&2
  exit 127
}
command -v vvp >/dev/null 2>&1 || {
  echo "ERROR: vvp missing from Icarus Verilog installation." >&2
  exit 127
}
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM
iverilog -g2012 -Wall -DMB_AY_CAPTURE_UNIT_TEST \
  -s tb_mb_ay_capture -o "$tmpdir/mb_ay_capture.vvp" \
  hdl/mockingboard/mockingboard.sv \
  tests/mb_doc/tb_mb_ay_capture.sv
vvp "$tmpdir/mb_ay_capture.vvp"

# Check all three DOC pitch calibrations against the identical source PCM.
# RES 2=original (no shift), 1=+1 octave, 0=+2 octaves.
for res in 0 1 2; do
  iverilog -g2012 -Wall -s tb_mb_doc_bridge \
    -Ptb_mb_doc_bridge.TEST_RES="$res" \
    -o "$tmpdir/mb_doc_bridge_res${res}.vvp" \
    boards/a2n20v2-Enhanced/hdl/mb_doc_bridge.sv \
    tests/mb_doc/tb_mb_doc_bridge.sv
  # DOC PCM ROM path is relative to the Enhanced Gowin project directory.
  (cd boards/a2n20v2-Enhanced && vvp "$tmpdir/mb_doc_bridge_res${res}.vvp")
done
