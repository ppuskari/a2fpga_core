# Enhanced FPGA audio ROM assets — clean-checkout build contract

This is part of the **M2 experimental branch**. Do not change the
hardware-validated J2R11 FPGA flash/MCU Stage2 binaries.

## What is present directly in Git

The FPGA project references these exact Gowin files, all tracked:

| Asset | Size / role | Reproducibility |
| --- | --- | --- |
| `hdl/ssi263_voice.mem` | 8,192 signed PCM phoneme approximation bytes | Original deterministic source in `tools/generate_ssi263_voice.py` |
| `hdl/ssi263_p8_params.mem` | Silicon-derived 64-phoneme parameter table | MIT-pinned SSI263 reference |
| `hdl/ssi263_p8_coefs.mem` | Formant DSP coefficients | Deterministic |
| `hdl/ssi263_p8_glottal.mem` | Source-excitation values | Deterministic |
| `hdl/ssi263_p9_f2nas.mem` | 256 F2/NAS coefficient combinations | Deterministic |
| `hdl/ssi263_p9_outfir.mem` | 193-tap output FIR | Deterministic |

All are validated against committed generators, including fresh-clone
GitHub Actions. The new voice bank is an **original approximation**, not
a proprietary SSI263 masked-ROM waveform dump. The pinned SSI263
silicon-model C source is MIT-licensed, with license and provenance
under `reference/ssi263/pico-v1.0.1/`.

## Exact authentic Apple SynthLAB piano bank

The current HDL uses **seven sustain zones from the Apple IIgs
SynthLAB PIANO.WAV**. The exact file consumed by
`hdl/mb_doc_bridge.sv` is:

`boards/a2n20v2-Enhanced/hdl/piano_multisustain.mem`

- **1,408 32-bit little-endian hex words = 5,632 bytes**.
- Sample source: `SEQ.AND.INSTR/PIANO.WAV` on the Apple IIgs System
  6.0.4 `synthLAB.po` disk.
- Source disk MD5: `fa4f143dd899d0cc4c8ed9c9e41b7d37`.
- Extracted packed PCM FNV32: `170BB8B3`.
- The preexisting extractor rejects incorrect disks, wrong wave metadata,
  missing zones, CRC/hash mismatch and DOC zero-stop bytes.

**The 5,632 bytes are Apple's original sampled audio**, not generated
by our project. They are still excluded from this publicly visible
repository. A noncommercial/hobby project does not by itself provide
redistribution permission. The build system handles this automatically
instead of substituting piano samples or risking silent DOC output.

## One command for Windows PowerShell 5.1

Run from the M2 branch checkout:

~~~powershell
.\Build-M2-FPGA.ps1 Prepare
~~~

That checks all committed SSI263 ROMs, downloads the pinned authentic
SynthLAB source **only if** the piano bank is missing, verifies the
source disk and each piano zone, creates `piano_multisustain.mem`,
and verifies the complete six-file SSI263 + piano inventory.

The second run does **not** download again. It checks cached samples.

For a full Gowin CLI build after asset preparation:

~~~powershell
.\Build-M2-FPGA.ps1 Build -GowinCli "C:\path\to\Gowin\IDE\bin\gw_sh.exe"
~~~

For **offline** work using your local 800KiB `synthLAB.po` image:

~~~powershell
.\Build-M2-FPGA.ps1 Prepare -Offline -SynthLABDisk "D:\AppleIIgs\synthLAB.po"
~~~

Or set `A2FPGA_SYNTHLAB_DISK` to the original image path and
`Build-M2-FPGA.ps1 Prepare -Offline` to regenerate on clean
offline clones.

Gowin GUI workflow: run `Prepare` before opening
`boards/a2n20v2-Enhanced/a2n20v2_enhanced.gprj`, then synthesize.
The `prebuild.tcl` guard is also updated, but the `.gprj` does not
declare an automatic prebuild hook; **do not assume the GUI executes
the TCL file**. The wrapper is the safe, explicit preparation point.

## Linux / macOS

The existing CLI builder now calls the same preparation tool before Gowin:

~~~bash
tools/build.sh a2n20v2-Enhanced all
~~~

Or run it separately:

~~~bash
python3 tools/prepare_enhanced_assets.py
python3 tools/prepare_enhanced_assets.py --check
~~~

The `--check` operation never downloads or modifies files, and a
missing/corrupt piano sample stops synthesis with a useful diagnostic.

### Scope boundaries

This fixes the **Enhanced** project resource/preload files needed for
the current combined Mockingboard/SSI263/DOC piano builds. It does not
convert Apple SynthLAB sample banks into distributable original work,
does not invent piano attacks/instruments the HDL doesn't use, and does
not affect the MCU MOD sample caches or PCM renderer.

The only expected build-side artifact absent from Git is
`piano_multisustain.mem`, produced automatically and validated.
A complete **offline** build still needs a locally available copy of
the original SynthLAB source disk or a previously extracted local ROM.
