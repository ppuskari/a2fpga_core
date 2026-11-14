#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/../.."
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT INT TERM
iverilog -g2012 -Wall -s tb_packet_direct_capture -o "$tmp" \
    hdl/hdmi/packet_picker.sv \
    hdl/hdmi/audio_clock_regeneration_packet.sv \
    hdl/hdmi/audio_sample_packet.sv \
    hdl/hdmi/auxiliary_video_information_info_frame.sv \
    hdl/hdmi/source_product_description_info_frame.sv \
    hdl/hdmi/audio_info_frame.sv \
    tests/mb_doc/tb_packet_direct_capture.sv
vvp "$tmp"
