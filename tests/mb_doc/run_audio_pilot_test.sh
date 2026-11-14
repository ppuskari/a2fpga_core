#!/usr/bin/env sh
# M6.4.2 post-DOC/right-channel HDMI pilot isolation regression.
set -eu
cd "$(dirname "$0")/../.."
command -v iverilog >/dev/null 2>&1 || { echo "Install iverilog" >&2; exit 127; }
command -v vvp >/dev/null 2>&1 || { echo "Install vvp" >&2; exit 127; }
out="$(mktemp)"
trap 'rm -f "$out"' EXIT INT TERM
iverilog -g2012 -Wall -s tb_mb_hdmi_audio_pilot \
  -o "$out" \
  boards/a2n20v2-Enhanced/hdl/mb_hdmi_audio_pilot.sv \
  tests/mb_doc/tb_mb_hdmi_audio_pilot.sv
vvp "$out"
