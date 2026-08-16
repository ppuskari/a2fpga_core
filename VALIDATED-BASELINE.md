# Validated a2fpga P0.x Baseline

## Purpose

This commit preserves the later P0.x validated a2n20v2-Enhanced FPGA build used by the Petars-Ensoniq-Kit integration.

## Ancestry

Official upstream base:
2735f128ab6019a5ea61825e09f5886915540521

Previous preservation snapshot:
f692c09acf570c4cb6ddc6167c6030c660448ab7

The previous snapshot and its tag remain immutable.

## Source validation

The critical Enhanced HDL and support source in GainStripped and Petars-Ensoniq-Kit were SHA256-identical, including:

- hdl/sound/doc5503.sv
- hdl/sound/sound_glu.sv
- hdl/debug/debugoverlay.sv
- boards/a2n20v2-Enhanced/hdl/top.sv
- tools/verify_doc_128k_protocol.py
- docs/adr/0002-doc-128k-explicit-unlock.md

The Petars-Ensoniq-Kit copy contained a later DOC_128K_EXTENSION_PROTOCOL.md clarification and a later complete Enhanced place-and-route build.

## Validated FPGA image

File:
boards/a2n20v2-Enhanced/impl/pnr/a2n20v2_enhanced.fs

Size:
7264150 bytes

SHA-256:
7C011DCCFD3955478307C568AA70BEBF305FAC11770B1289229B1FF593AA9169

Original observed timestamp:
2026-08-03 03:35:47

The complete differing PnR artifact set is recorded in P0X-PNR-SHA256.txt.
