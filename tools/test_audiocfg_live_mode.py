#!/usr/bin/env python3
"""Source-only checks; not a Gowin simulation, synthesis or MCU compiler."""
from pathlib import Path
import re

r = Path(__file__).resolve().parents[1]
b = r / "boards/a2n20v2-Enhanced"
rtl = (b / "hdl/bl616/bl616_spi_connector.sv").read_text(encoding="utf-8")
top = (b / "hdl/top.sv").read_text(encoding="utf-8")
menu = (b / "src/a2n20_bl616/firmware_host/menu.c").read_text(encoding="utf-8")
main = (b / "src/a2n20_bl616/firmware_host/main.c").read_text(encoding="utf-8")
disk = (b / "src/a2n20_bl616/firmware_host/disk.c").read_text(encoding="utf-8")
assert "audio_mode_locked_r" not in rtl, "Lock still exists"
assert "7'h6B: slot_reconfig_r <= 1'b1; // slots ONLY" in rtl
assert "end else if (reg_wdata[7:2] == 6'd0) begin" in rtl
assert "audio_mode_r <= reg_wdata[1:0];" in rtl
assert "7'h6F: reg_rdata = {6'b101000, audio_mode_r};" in rtl
assert "7'h6B: reg_rdata = {6'b110100, audio_active_route_i};" in rtl
for i, name in enumerate(("audio_enhanced_w", "audio_original_w",
                          "audio_native_w", "audio_shared_w")):
    # RTL aligns declarations with variable spaces before '='. Match
    # Verilog tokens, not pretty-printing or indentation.
    pattern = rf"\bwire\s+{re.escape(name)}\s*=\s*AUDIO_MODE_MB_DOC\s*&&\s*\(\s*mcu_audio_mode_w\s*==\s*2'd{i}\s*\)\s*;"
    assert re.search(pattern, top), f"{name} must select AUDIO_MODE_MB_DOC personality {i}"
assert "settings()->audio_mode = s_audio_draft;" in menu
assert "fpga_spi_reg_write(REG_AUDIO_MODE, s_audio_draft);" in menu
assert "AUD LIVE S=%u F=%02X RT=%02X %s" in menu
assert "MODE APPLIES IMMEDIATELY" in menu
assert "fpga_spi_reg_write(0x6Fu, 0xF0u);" not in main
assert "fpga_spi_reg_write(0x6Fu, 0xF0u);" not in menu
assert "fpga_spi_reg_write(0x2E" not in main
assert "fpga_spi_reg_write(0x2E, 1);" in disk
assert main.index("menu_audio_apply_saved_early();") < main.index("fpga_spi_reg_write(0x6B, 1);")
assert "menu_audio_apply_saved_before_release();" in disk
assert disk.index("menu_audio_apply_saved_before_release();") < disk.index("fpga_spi_reg_write(REG_CARDROM_REL, 1);")
assert disk.index("menu_audio_apply_saved_before_release();") < disk.index("fpga_spi_reg_write(0x2E, 1);")
print("PASS: unlocked FPGA mode, menu save applies live, M641 startup preserved")
print("SOURCE-ONLY: MCU/FPGA builds and hardware validation pending")
