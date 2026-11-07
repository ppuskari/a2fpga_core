#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
iverilog -g2012 -s tb_ssi263_native -o /tmp/a2fpga_p7_ssi263_native.vvp \
  hdl/mockingboard/ssi263_native_rom.sv \
  hdl/mockingboard/ssi263_native_voice.sv \
  tests/mb_ssi263/tb_ssi263_native.sv
vvp /tmp/a2fpga_p7_ssi263_native.vvp
