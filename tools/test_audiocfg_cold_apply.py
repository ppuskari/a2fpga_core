#!/usr/bin/env python3
"""A3 saved audio startup: early write and pre-reset retry, no Apple reset."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
h = root / "boards/a2n20v2-Enhanced/src/a2n20_bl616/firmware_host"
main = (h / "main.c").read_text(encoding="utf-8")
disk = (h / "disk.c").read_text(encoding="utf-8")
menu = (h / "menu.c").read_text(encoding="utf-8")
header = (h / "menu.h").read_text(encoding="utf-8")
settings = (h / "settings.c").read_text(encoding="utf-8")

# Only saved flash mode is used by both boot stages, with no default 0 overwrite.
assert 'const uint8_t wanted = settings()->audio_mode;' in menu
assert 'settings_init();' in main
assert main.index('settings_init();') < main.index('menu_audio_apply_saved_early();')
assert main.index('menu_audio_apply_saved_early();') < main.index('fpga_spi_reg_write(0x6B, 1);')
assert 's_cfg.audio_mode  = AUDIO_MB_ENHANCED;' in settings
assert 's_cfg = blob;' in settings
assert 'void menu_audio_apply_saved_early(void)' in menu
assert 'void menu_audio_apply_saved_before_release(void)' in menu
for name in ('menu_audio_apply_saved_early', 'menu_audio_apply_saved_before_release'):
    assert ('void ' + name + '(void);') in header
assert menu.count('fpga_spi_reg_write(REG_AUDIO_MODE, wanted);') == 1
assert 'for (int attempt = 0; attempt < 16 && !verified; ++attempt)' in menu
assert 'request == (uint8_t)(0xA0u | wanted)' in menu
assert 'route == (uint8_t)(0xD0u | wanted)' in menu
assert 'diag->verified = verified;' in menu
assert 'diag->attempted = true;' in menu
assert 'AUD %s S=%u F=%02X RT=%02X %s N=%d' in menu

# Retry exactly once on initial release, not on every poll/remount.
assert disk.count('menu_audio_apply_saved_before_release();') == 1
start = disk.index('if (!s_released)')
retry = disk.index('menu_audio_apply_saved_before_release();')
cardrom = disk.index('fpga_spi_reg_write(REG_CARDROM_REL, 1);')
release = disk.index('fpga_spi_reg_write(0x2E, 1);')
assert start < retry < cardrom < release
assert disk.index('fpga_spi_reg_write(0x6B, 1);') < retry
assert disk.index('if ((any && !g_remount_req) ||') < retry

# Persist diagnostics even after startup console scrolls away.
assert 'BOOT CONFIG SOURCE' in menu
assert 'BOOT EARLY SPI' in menu
assert 'BOOT PRE-RESET' in menu
assert 'audio_boot_status(' in menu
assert 's_audio_boot_early' in menu and 's_audio_boot_before_release' in menu

# Preserve hardware-proven LIVE path and prohibit boot reset / F0.
assert 'fpga_spi_reg_write(REG_AUDIO_MODE, s_audio_draft);' in menu
assert 'if (settings_save())' in menu
assert 'AUD LIVE S=%u F=%02X RT=%02X %s' in menu
assert 'fpga_spi_reg_write(REG_AUDIO_MODE, 0xF0' not in menu
assert 'fpga_spi_reg_write(0x6Fu, 0xF0u)' not in main
assert 'fpga_spi_reg_write(0x2E' not in main
assert 'fpga_spi_reg_write(REG_SLOT_RECONFIG' not in menu[menu.index('static void audio_save('):menu.index('static void audio_build(')]

print("PASS: flash-saved mode early + pre-release verified, live mode preserved")
print("SOURCE-ONLY: cross-compile and real IIe cold boot still required")
