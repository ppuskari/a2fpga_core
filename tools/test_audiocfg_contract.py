#!/usr/bin/env python3
"""AUDIOCFG A1/A2/A3 source contract checks (no FPGA simulator required).

This verifies cross-language numeric encodings and the source-level
ownership gates. It does NOT establish Gowin synthesis or hardware
timing/audio correctness. Invoke from the repository root:
    python tools/test_audiocfg_contract.py
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "boards" / "a2n20v2-Enhanced"
H = (BOARD / "src/a2n20_bl616/firmware_host/settings.h").read_text()
TOP = (BOARD / "hdl/top.sv").read_text()
GLU = (ROOT / "hdl/sound/sound_glu.sv").read_text()
SPI = (BOARD / "hdl/bl616/bl616_spi_connector.sv").read_text()
SPI_HOST = (BOARD / "src/a2n20_bl616/firmware/fpga_spi.c").read_text()
MENU = (BOARD / "src/a2n20_bl616/firmware_host/menu.c").read_text()

MODE = {
    "AUDIO_MB_ENHANCED": 0,
    "AUDIO_MB_ORIGINAL": 1,
    "AUDIO_DOC_NATIVE": 2,
    "AUDIO_SHARED": 3,
}
for name, value in MODE.items():
    assert re.search(rf"#define\s+{name}\s+{value}u\b", H), name

# Model the gates in top.sv and assert the mutually exclusive ownership
# truth table, then verify each referenced condition is present in the HDL.
for mode in range(4):
    enhanced = mode == 0
    original = mode == 1
    native = mode == 2
    shared = mode == 3
    doc_bridge = enhanced
    doc_cpu = native or shared
    mb_visible = not native
    ay_audio = original or shared
    assert not (doc_bridge and doc_cpu), mode
    assert mb_visible == (enhanced or original or shared), mode
    assert ay_audio == (original or shared), mode
    assert doc_bridge or doc_cpu or original, mode

for needle in [
    "audio_enhanced_w = AUDIO_MODE_MB_DOC && (mcu_audio_mode_w == 2'd0)",
    "audio_original_w = AUDIO_MODE_MB_DOC && (mcu_audio_mode_w == 2'd1)",
    "audio_native_w   = AUDIO_MODE_MB_DOC && (mcu_audio_mode_w == 2'd2)",
    "audio_shared_w   = AUDIO_MODE_MB_DOC && (mcu_audio_mode_w == 2'd3)",
    ".reset_n_i(system_reset_n_w && audio_enhanced_w)",
    ".active_i(audio_mb_enabled_w)",
    "audio_shared_w ? shared_mix_l_w",
    "audio_enhanced_w ? (mb_fx_ay_l_w ? mb_fx_pcm_l : sg_audio_l)",
    "wire native_doc_slot_w = AUDIO_MODE_MB_DOC && audio_native_doc_w",
    ".audio_active_route_i(audio_active_route_w)",
]:
    assert needle in TOP, needle
for needle in [
    "mb_owner_w = MB_DOC_MODE && (audio_mode_i == 2'd0)",
    "native_owner_w = !MB_DOC_MODE || (audio_mode_i[1])",
    "native_slot_sel_i && (a2bus_if.addr[3:2] == 2'b00)",
    "mb_owner_w ? mb_doc_wr_i : doc_wr_r",
    ".cs_n_i(~(doc_host_wr_w || doc_host_rd_w))",
    "doc_shadow[scrub_ptr_r] <= 8'h00",
]:
    assert needle in GLU, needle
for needle in ["7'h6F: reg_rdata = {6'b101000, audio_mode_r}",
               "7'h6B: reg_rdata = {6'b110100, audio_active_route_i}",
               "reg_wdata == 8'hF0",
               "audio_boot_rearm_pulse_r <= 1'b1",
               "audio_mode_locked_r <= 1'b1",
               "7'h6F: begin",
               "audio_mode_r <= reg_wdata[1:0]"]:
    assert needle in SPI, needle
# The SPI write must hold CS# through the FPGA SCLK->system CDC commit,
# including the raw register write variant. Without this a rapid CS# rise
# may discard the second byte before reg_wr_req is generated.
assert "#define FPGA_SPI_REG_WRITE_CS_HOLD_US 3u" in SPI_HOST
assert SPI_HOST.count("bflb_mtimer_delay_us(FPGA_SPI_REG_WRITE_CS_HOLD_US);") == 2
assert "SAVE FOR NEXT BOOT (ENTER)" in MENU
assert "FPGA ACTIVE AUDIO" in MENU
assert "A3 VERIFIED" in MENU
assert "SAVED != ACTIVE" in MENU
assert "0x6Bu" in (BOARD / "src/a2n20_bl616/firmware_host/main.c").read_text()
assert "fpga_spi_reg_write(0x6Fu, 0xF0u)" in (BOARD / "src/a2n20_bl616/firmware_host/main.c").read_text()
assert 'AUDIOCFG S=%u FPGA=%02X RT=%02X %s' in (BOARD / "src/a2n20_bl616/firmware_host/disk.c").read_text()
MAIN = (BOARD / "src/a2n20_bl616/firmware_host/main.c").read_text()
DISK = (BOARD / "src/a2n20_bl616/firmware_host/disk.c").read_text()
assert "bool audiocfg_ensure_boot_mode(bool *did_rearm)" in MAIN
assert "g_audio_applied_early = ready && audiocfg_ensure_boot_mode(NULL)" in MAIN
assert "if (ok && g_audio_applied_early)" in MAIN
assert "audio_ok = audiocfg_ensure_boot_mode(&audio_rearmed)" in DISK
assert "if ((!g_slots_applied_early || audio_rearmed) && audio_ok)" in DISK
assert "bool slots_commit_ok = g_slots_applied_early && !audio_rearmed;" in DISK
assert "if (audio_ok && slots_commit_ok)" in DISK
assert "BOOT: APPLE RUNNING; NO LATE RESET" in DISK
assert "if (st & FPGA_STATUS_A2BUS_RESET_N)" in MAIN
assert "RST_MCU_ALIVE_WAIT = CLOCK_SPEED_HZ * 12" in SPI
assert "RST_HOLD_BACKSTOP  = CLOCK_SPEED_HZ * 25" in SPI
assert "fpga_spi_reg_write(0x6Fu, 0xF0u);" in MENU
assert "slots_verified" in DISK

print("AUDIOCFG A1/A2/A3 source contracts: PASS (not a synthesis test)")
