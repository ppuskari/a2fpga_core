# Validated a2fpga Baseline

## Purpose

This commit preserves the exact a2fpga source and FPGA image used for the validated Apple IIgs Ensoniq DOC work.

## Upstream ancestry

Repository: a2fpga/a2fpga_core

Upstream base commit:
2735f128ab6019a5ea61825e09f5886915540521

Upstream base description:
a2n20v2-GS/Enhanced: share one apple_bus and SDRAM apple_memory

Upstream base date:
2026-07-05

## Validated target

Board:
boards/a2n20v2-Enhanced

FPGA image:
boards/a2n20v2-Enhanced/impl/pnr/a2n20v2_enhanced.fs

Image size:
7264150 bytes

SHA-256:
0E9BC43E58A7D8F70A755F05943DB181B01067BAC27380EFE5FF3F8F5FF4F9C4

Observed file timestamp:
2026-08-03 00:34:12

## Source scope

This baseline includes the corresponding Ensoniq DOC5503, Sound GLU, Enhanced top-level, debug, documentation, protocol verification, and related source changes present in the validated working tree.

The FPGA .fs artifact is explicitly marked -text in .gitattributes so Git preserves it byte-for-byte.

Generated a2n20v2-GS PnR differences that were present in the local archive are not part of this validated Enhanced baseline.

## Reproducibility

The Git commit identifies the complete preserved source tree.
GOLDEN-SHA256.txt identifies the hardware-validated FPGA artifact.
