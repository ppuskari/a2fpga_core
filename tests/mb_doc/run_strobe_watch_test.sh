#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/../.."
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT INT TERM
iverilog -g2012 -Wall -s tb_audio_strobe_watch -o "$tmp" boards/a2n20v2-Enhanced/hdl/mb_audio_strobe_watch.sv tests/mb_doc/tb_audio_strobe_watch.sv
vvp "$tmp"
