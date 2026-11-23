#!/usr/bin/env python3
"""M3 Gowin 1.9.9 headless project generation regression.

Test the actual committed .gprj source list, including M3 SD burst receiver.
A checked-in piano_multisustain.mem is deliberately NOT required in CI:
the test mocks only that generated asset's existence while generating Tcl,
and never compiles or fabricates substitute instrument data.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
BOARD = ROOT / "boards" / "a2n20v2-Enhanced"
PROJECT = BOARD / "a2n20v2_enhanced.gprj"
GENERATOR = ROOT / "tools" / "generate_m3_gowin_tcl.py"
assert ROOT.is_dir(), ROOT

spec = importlib.util.spec_from_file_location("m3gen", GENERATOR)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

xml_root = ET.parse(PROJECT).getroot()
items = xml_root.findall("./FileList/File")
enabled = [e for e in items if e.get("enable") == "1"]
expected_add_files = sum(e.get("type") != "file.other" for e in enabled)
memory_files = {e.get("path") for e in enabled if e.get("type") == "file.other"}
assert "hdl/piano_multisustain.mem" in memory_files
assert any("fpga_sd_burst.sv" in e.get("path", "") for e in enabled)

original_is_file = Path.is_file


def verified_project_with_unavailable_generated_piano(self: Path) -> bool:
    """CI may lack the private piano sample ROM; NEVER supply dummy bytes."""
    if (self.name == "piano_multisustain.mem" and
            self.parent.resolve() == (BOARD / "hdl").resolve()):
        return True
    return original_is_file(self)


with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    path = root / "m3-build.tcl"
    with patch.object(Path, "is_file", verified_project_with_unavailable_generated_piano):
        result = module.generate(PROJECT, path, "all")
    text = path.read_text(encoding="utf-8")
    assert result["sources"] == expected_add_files
    assert result["data_files"] == len(memory_files)
    assert text.count("    add_file -type ") == expected_add_files
    assert "set_device -name {GW2AR-18C} {GW2AR-LV18QN88C8/I7}" in text
    assert "source {prebuild.tcl}" in text
    assert "set_option -top_module {top}" in text
    assert "set_option -verilog_std sysv2017" in text
    assert "set_option -output_base_name {a2n20v2_enhanced}" in text
    assert "run all" in text and "M3_GOWIN_TCL_COMPLETED" in text
    assert "open_project" not in "\n".join(
        line for line in text.splitlines()
        if not line.lstrip().startswith("#")
    )
    assert "hdl/bl616/fpga_sd_burst.sv" in text
    assert "hdl/bl616/bl616_spi_proto_proc.sv" in text
    assert "../../hdl/mockingboard/mockingboard.sv" in text
    assert "hdl/a2n20v2_enhanced.cst" in text
    assert "hdl/a2n20v2_enhanced.sdc" in text
    assert "    add_file -type other " not in text

    with patch.object(Path, "is_file", verified_project_with_unavailable_generated_piano):
        result_syn = module.generate(PROJECT, root / "m3-syn.tcl", "syn")
    assert "    run syn" in (root / "m3-syn.tcl").read_text()
    assert result_syn["sources"] == expected_add_files

    # Verify fail-closed if an actual HDL source is missing, not just one of
    # the generated ROMs that CI lacks.
    def fail_on_core(self: Path) -> bool:
        if self.name == "fpga_sd_burst.sv":
            return False
        return verified_project_with_unavailable_generated_piano(self)

    with patch.object(Path, "is_file", fail_on_core):
        try:
            module.generate(PROJECT, root / "broken.tcl", "all")
        except RuntimeError as e:
            assert "Missing project source" in str(e)
        else:
            raise AssertionError("Generator accepted missing burst receiver")

wrapper = (ROOT / "Build-M3-FPGA.ps1").read_text(encoding="utf-8")
for expected in (
    "generate_m3_gowin_tcl.py", "Start-Process",
    "M3_GOWIN_TCL_COMPLETED", "m3-previous-artifacts",
    "Get-FileHash", "Gowin logged a synthesis/project/Tcl error",
    "No available design files found in this project",
    "-RedirectStandardOutput", "-RedirectStandardError",
):
    assert expected in wrapper, expected
assert "$cmds | & $GowinCli" not in wrapper
assert "$quotedScript='\"'+$tclScript+'\"'" in wrapper

print(
    f"PASS M3 Gowin 1.9.9: {expected_add_files} real sources,"
    f" {len(memory_files)} verified-only data files,"
    " generated Tcl and fail-closed PowerShell guard"
)
