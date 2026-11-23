#!/usr/bin/env python3
"""Source-level M3 boot-video regression: Apple video is cold-boot default.

This verifies the specific switch/ownership points changed by M3 Apple-first;
it is intentionally NOT a replacement for BL616 host compilation or hardware.
"""
from pathlib import Path

BOARD = Path(__file__).resolve().parents[1]
HOST = BOARD / "src/a2n20_bl616/firmware_host"
conn = (BOARD / "hdl/bl616/bl616_spi_connector.sv").read_text()
disk = (HOST / "disk.c").read_text()
menu = (HOST / "menu.c").read_text()
hid = (HOST / "usbh_hidinput.c").read_text()
osd = (HOST / "osd_console.c").read_text()

# FPGA power-on defaults to native Apple bus video, unaffected by Tcl synthesis.
assert "video_enable_r    <= 1'b0;" in conn
assert "assign video_control_if.enable                = video_enable_r;" in conn

# Disk mounting never steals the HDMI source and never installs a
# delayed hide that could race TAB while the user is reading the console.
mount = disk.split("static void disk_remount(void)", 1)[1].split(
    "void disk_init(void)", 1)[0]
poll = disk.split("void disk_poll(void)", 1)[1]
assert 'osd_log("DISK II: SEARCHING FOR STORAGE...")' in mount
assert "osd_console_show();" not in mount
assert "osd_console_hide();" not in mount
assert "schedule_console_hide" not in disk
assert "g_hide_console_at_us" not in disk
assert "osd_console_hide();" not in poll
assert 'osd_log("DISK II: NO DISK IMAGES ON VOLUME")' in mount

# TAB opens the console first, Y swaps to the menu, TAB toggles back.
assert "static view_t s_view       = VIEW_APPLE;" in menu
assert "static view_t s_mcu_view   = VIEW_CONSOLE;" in menu
assert "if (btn == XINPUT_BACK)" in menu
assert "enter_view(s_mcu_view);" in menu
assert "enter_view(VIEW_APPLE);" in menu
assert "osd_console_show();" in menu
assert "osd_console_hide();" in menu
assert "case 0x2B: return XINPUT_BACK;" in hid
assert "case 0x1C: return XINPUT_X;" in hid

# Boot diagnostics are buffered regardless of video selection; TAB retrieves
# them with the existing OSD, without an always-running background redraw.
assert "if (s_visible)" in osd
assert "telnetd_console_tee(line);" in osd
assert "fpga_spi_reg_write(REG_VIDEO_ENABLE, 1);" in osd
print("PASS M3 Apple-first: native video at reset, disk logs buffered, TAB console, Y menu, no delayed hide race")
