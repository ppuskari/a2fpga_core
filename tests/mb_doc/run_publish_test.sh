#!/usr/bin/env sh
# M6.4.1 coherent DOC publication: Icarus + existing M6.4 compatibility tests.
set -eu
cd "$(dirname "$0")/../.."
command -v iverilog >/dev/null 2>&1 || { echo "ERROR: install Icarus Verilog" >&2; exit 127; }
command -v vvp >/dev/null 2>&1 || { echo "ERROR: vvp missing" >&2; exit 127; }
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM
for res in 0 1 2; do
  iverilog -g2012 -Wall -s tb_mb_doc_publish \
    -Ptb_mb_doc_publish.TEST_RES="$res" \
    -o "$tmpdir/mb_doc_publish_res${res}.vvp" \
    boards/a2n20v2-Enhanced/hdl/mb_doc_bridge.sv \
    tests/mb_doc/tb_mb_doc_publish.sv
  (cd boards/a2n20v2-Enhanced && vvp "$tmpdir/mb_doc_publish_res${res}.vvp")
done
