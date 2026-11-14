#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/../.."
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT INT TERM
iverilog -g2012 -Wall -s tb_packet_direct_capture -o "$tmp" \
    hdl/hdmi/packet_picker.sv tests/mb_doc/tb_packet_direct_capture.sv
vvp "$tmp"
