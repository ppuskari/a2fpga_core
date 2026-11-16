#!/usr/bin/env sh
# M6.5a AY noise / envelope / mixer event detector (Icarus Verilog).
set -eu
cd "$(dirname "$0")/../.."
command -v iverilog >/dev/null 2>&1 || { echo "Install iverilog" >&2; exit 127; }
command -v vvp >/dev/null 2>&1 || { echo "Install vvp" >&2; exit 127; }
bin="$(mktemp)"
trap 'rm -f "$bin"' EXIT INT TERM
iverilog -g2012 -Wall -s tb_mb_doc_fx_events -o "$bin" \
    boards/a2n20v2-Enhanced/hdl/mb_doc_fx_events.sv \
    tests/mb_doc/tb_mb_doc_fx_events.sv
vvp "$bin"
