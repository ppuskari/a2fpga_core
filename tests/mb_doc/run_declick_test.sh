#!/usr/bin/env sh
# M6.4 optional de-click, six-voice DOC-only regression.
set -eu
cd "$(dirname "$0")/../.."
command -v iverilog >/dev/null 2>&1 || { echo "Install iverilog." >&2; exit 127; }
command -v vvp >/dev/null 2>&1 || { echo "Install vvp." >&2; exit 127; }
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM
for res in 0 1 2; do
  iverilog -g2012 -Wall -s tb_mb_doc_declick \
    -Ptb_mb_doc_declick.TEST_RES="$res" \
    -o "$tmpdir/mb_doc_declick_res${res}.vvp" \
    boards/a2n20v2-Enhanced/hdl/mb_doc_bridge.sv \
    tests/mb_doc/tb_mb_doc_declick.sv
  (cd boards/a2n20v2-Enhanced && vvp "$tmpdir/mb_doc_declick_res${res}.vvp")
done
