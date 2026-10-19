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
