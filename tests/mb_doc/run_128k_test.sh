#!/usr/bin/env sh
# M6.6a independent 128KiB DOC sound-bank preload and OSC6/7 bank selection.
set -eu
cd "$(dirname "$0")/../.."
command -v iverilog >/dev/null 2>&1 || { echo "iverilog required" >&2; exit 127; }
command -v vvp >/dev/null 2>&1 || { echo "vvp required" >&2; exit 127; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
iverilog -g2012 -Wall -s tb_mb_doc_128k -o "$tmp/dual.vvp" \
    boards/a2n20v2-Enhanced/hdl/mb_doc_fx_wavegen.sv \
    boards/a2n20v2-Enhanced/hdl/mb_doc_fx_events.sv \
    boards/a2n20v2-Enhanced/hdl/mb_doc_bridge.sv \
    tests/mb_doc/tb_mb_doc_128k.sv
(cd boards/a2n20v2-Enhanced && vvp "$tmp/dual.vvp")
