#!/usr/bin/env sh
# M6.6b per-channel, dual-chip native YM FX routing regressions.
set -eu
cd "$(dirname "$0")/../.."
command -v iverilog >/dev/null 2>&1 || { echo "Icarus Verilog required" >&2; exit 127; }
command -v vvp >/dev/null 2>&1 || { echo "vvp required" >&2; exit 127; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
iverilog -g2012 -Wall -s tb_mb_doc_ay_fx_router -o "$tmp/router.vvp" \
    boards/a2n20v2-Enhanced/hdl/mb_doc_ay_fx_router.sv \
    tests/mb_doc/tb_mb_doc_ay_fx_router.sv
vvp "$tmp/router.vvp"
iverilog -g2012 -Wall -s tb_mb_doc_fx_parity -o "$tmp/bridge.vvp" \
    boards/a2n20v2-Enhanced/hdl/mb_doc_ay_fx_router.sv \
    boards/a2n20v2-Enhanced/hdl/mb_doc_fx_events.sv \
    boards/a2n20v2-Enhanced/hdl/mb_doc_fx_wavegen.sv \
    boards/a2n20v2-Enhanced/hdl/mb_doc_bridge.sv \
    tests/mb_doc/tb_mb_doc_fx_parity.sv
(cd boards/a2n20v2-Enhanced && vvp "$tmp/bridge.vvp")
