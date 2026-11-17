#!/usr/bin/env python3
"""A3-R6 boot-order contracts: source invariant checks, not hardware tests."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
B = ROOT / "boards" / "a2n20v2-Enhanced"
M = (B / "src/a2n20_bl616/firmware_host/main.c").read_text()
D = (B / "src/a2n20_bl616/firmware_host/disk.c").read_text()
U = (B / "src/a2n20_bl616/firmware_host/menu.c").read_text()
F = (B / "src/a2n20_bl616/firmware/fpga_spi.c").read_text()
S = (B / "hdl/bl616/bl616_spi_connector.sv").read_text()
T = (B / "hdl/top.sv").read_text()
assert "bool audiocfg_boot_select(void)" in M
assert "bool audiocfg_virtual_storage_assigned(void)" in M
assert "fpga_spi_reg_write(REG_A2BUS_READY, 1);" in M
assert "fpga_spi_reg_read(REG_A2BUS_READY)" in M
assert "audio_boot_ok = audiocfg_boot_select();" in M
assert "if (ok && audio_boot_ok && bus_ready_ack)" in M
assert "fpga_spi_reg_write(0x6B, 1)" in M
assert "fpga_spi_reg_write(0x2E" not in M
assert "fpga_spi_reg_write(0x6Fu, 0xF0u)" not in M
assert "fpga_spi_reg_write(0x6Fu, mode);" in M
assert M.index("fpga_spi_init();") < M.index("settings_init();") < M.index("audio_boot_ok = audiocfg_boot_select();") < M.index("fpga_spi_reg_write(0x6B, 1)") < M.index("usbh_initialize(") < M.index('usb_osal_thread_create("disk"')
assert "if (!audiocfg_virtual_storage_assigned()" in D
assert "int audio_ok = bridge_ok && audiocfg_boot_select();" in D
assert "if (audio_ok && slots_ok)" in D
assert "fpga_spi_reg_write(REG_CARDROM_REL, 1);" in D
assert "fpga_spi_reg_write(0x2Eu, 1);" in D
assert D.index("fpga_spi_reg_write(REG_CARDROM_REL, 1)") < D.index("fpga_spi_reg_write(0x2Eu, 1)")
assert "fpga_spi_reg_write(0x6Fu, 0xF0u)" not in D
assert "fpga_spi_reg_write(0x6Fu, 0xF0u)" in U
assert "SAVED != ACTIVE" in U
assert "FPGA_SPI_REG_WRITE_CS_HOLD_US 3u" in F
assert "reg_wdata == 8'hF0" in S
assert "audio_mode_r <= reg_wdata[1:0]" in S
assert "audio_original_w ? mb_fx_pcm_l" in T
assert "audio_original_w ? mb_fx_pcm_r" in T
print("A3-R6 boot-order source contract: PASS (not Gowin or BL616 compilation)")
