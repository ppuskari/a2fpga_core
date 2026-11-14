#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/../.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
verilator --binary --timing -j 4 -Wno-fatal --top-module tb_packet_direct_capture --Mdir "$tmp/obj_dir" \
    hdl/hdmi/packet_picker.sv \
    hdl/hdmi/audio_clock_regeneration_packet.sv \
    hdl/hdmi/audio_sample_packet.sv \
    hdl/hdmi/auxiliary_video_information_info_frame.sv \
    hdl/hdmi/source_product_description_info_frame.sv \
    hdl/hdmi/audio_info_frame.sv \
    tests/mb_doc/tb_packet_direct_capture.sv
"$tmp/obj_dir/Vtb_packet_direct_capture"
