#!/usr/bin/env sh
# M6.5b: exact procedural FX table marker + real bridge host sequence.
set -eu
cd "$(dirname "$0")/../.."
command -v iverilog >/dev/null 2>&1 || exit 127
command -v vvp >/dev/null 2>&1 || exit 127
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
iverilog -g2012 -Wall -s tb_mb_doc_fx_wavegen -o "$tmp/bank.vvp" \
    boards/a2n20v2-Enhanced/hdl/mb_doc_fx_wavegen.sv \
    tests/mb_doc/tb_mb_doc_fx_wavegen.sv
vvp "$tmp/bank.vvp"
iverilog -g2012 -Wall -s tb_mb_doc_fx_playback -o "$tmp/play.vvp" \
    boards/a2n20v2-Enhanced/hdl/mb_doc_fx_wavegen.sv \
    boards/a2n20v2-Enhanced/hdl/mb_doc_ay_fx_router.sv \
    boards/a2n20v2-Enhanced/hdl/mb_doc_fx_events.sv \
    boards/a2n20v2-Enhanced/hdl/mb_doc_bridge.sv \
    tests/mb_doc/tb_mb_doc_fx_playback.sv
(cd boards/a2n20v2-Enhanced && vvp "$tmp/play.vvp")
