#!/usr/bin/env python3
"""Source-only checks; not a Gowin simulation, synthesis or MCU compiler."""
from pathlib import Path
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
for i,name in enumerate(("audio_enhanced_w","audio_original_w","audio_native_w","audio_shared_w")):
    assert f"{name} = AUDIO_MODE_MB_DOC && (mcu_audio_mode_w == 2'd{i})" in top
assert "settings()->audio_mode = s_audio_draft;" in menu
assert "fpga_spi_reg_write(REG_AUDIO_MODE, s_audio_draft);" in menu
assert "AUD LIVE S=%u F=%02X RT=%02X %s" in menu
assert "MODE APPLIES IMMEDIATELY" in menu
assert "fpga_spi_reg_write(0x6Fu, 0xF0u);" not in main
assert "fpga_spi_reg_write(0x6Fu, 0xF0u);" not in menu
assert "fpga_spi_reg_write(0x2E" not in main
assert "fpga_spi_reg_write(0x2E, 1);" in disk
assert main.index("fpga_spi_reg_write(0x6Fu, wanted);") < main.index("fpga_spi_reg_write(0x6B, 1);")
print("PASS: unlocked FPGA mode, menu save applies live, M641 startup preserved")
print("SOURCE-ONLY: MCU/FPGA builds and hardware validation pending")
