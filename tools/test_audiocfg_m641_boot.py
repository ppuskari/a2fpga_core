#!/usr/bin/env python3
"""M641-safe AUDIOCFG boot/source checks. Not FPGA synthesis or MCU build."""
from pathlib import Path
import hashlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
B = ROOT / "boards" / "a2n20v2-Enhanced"
H = B / "src/a2n20_bl616/firmware_host"
m = (H / "main.c").read_text()
d = (H / "disk.c").read_bytes()
menu = (H / "menu.c").read_text()
settings_h = (H / "settings.h").read_text()
settings_c = (H / "settings.c").read_text()
spi = (B / "src/a2n20_bl616/firmware/fpga_spi.c").read_text()

def git_blob(data):
    # Git stores canonical LF text; Windows checkouts may contain CRLF.
    # Normalize only CRLF, preserving all other bytes for strict checking.
    data = data.replace(bytes([13, 10]), bytes([10]))
    return hashlib.sha1(("blob %d" % len(data)).encode() + bytes([0]) + data).hexdigest()

# The validated M641 physical boot and reset code must remain untouched.
assert git_blob(d) == "0e8a7b7c687a434077e78001e205e309f61d12ee"
# Every byte of M641 main.c OUTSIDE the single audio-selection block is
# unchanged. This protects native Slot 6 disk autoboot, USB and reset order.
start = m.index("    /* AUDIOCFG: M641 still owns")
end = m.index("    /* Apply the persisted slot map EARLY", start)
# Compare the actual file contents, not a source hash that may have been
# produced before line-ending normalization by the repository API.
# The M641 reference commit is an ancestor of this branch and is available
# locally in the normal clone without any remote branch checkout.
M641_COMMIT = "8af7df27156e1a95b5346b9851e20d69697786d8"
MAIN_PATH = "boards/a2n20v2-Enhanced/src/a2n20_bl616/firmware_host/main.c"
m641_main = subprocess.check_output(
    ["git", "show", f"{M641_COMMIT}:{MAIN_PATH}"], cwd=ROOT
).replace(bytes([13, 10]), bytes([10]))
current_without_audio = (m[:start] + m[end:]).encode("utf-8")
assert current_without_audio == m641_main, (
    "M641 main.c changed outside AUDIOCFG early selection"
)
assert "#define SETTINGS_VERSION  3" in settings_h
for x in ("AUDIO_MB_ENHANCED 0u", "AUDIO_MB_ORIGINAL 1u",
          "AUDIO_DOC_NATIVE  2u", "AUDIO_SHARED      3u"):
    assert x in settings_h, x
assert "uint8_t  audio_mode;" in settings_h
assert "uint8_t  reserved[12];" in settings_h
assert "s_cfg.audio_mode  = AUDIO_MB_ENHANCED;" in settings_c
assert "SAVED != ACTIVE" in menu
assert "FULL POWER CYCLE TO APPLY" in menu

steps = ("fpga_spi_init();", "fpga_spi_reg_write(REG_A2BUS_READY, 1);",
         "settings_init();", "const uint8_t wanted = settings()->audio_mode;",
         "fpga_spi_reg_write(0x6Fu, wanted);", "fpga_spi_reg_write(0x6B, 1);",
         "usbh_initialize(0, CONFIG_USB_EHCI_HCCR_BASE);",
         'usb_osal_thread_create("disk"')
indices = [m.index(x) for x in steps]
assert indices == sorted(indices), "Unexpected M641 startup ordering"
assert "ack == (uint8_t)(0xA0u | wanted)" in m
assert "route == (uint8_t)(0xD0u | wanted)" in m
assert 'matched ? "OK" : "FALLBACK"' in m

# No early Apple /RESET manipulation or MCU-only warm FPGA mode rearm.
assert "fpga_spi_reg_write(0x2E" not in m
# Exactly one protected F0 in main(), never in disk.c or menu.
assert m.count("fpga_spi_reg_write(0x6Fu, 0xF0u);") == 1
assert "if (!(reset_status & FPGA_STATUS_A2BUS_RESET_N) &&" in m
assert "!(release_reg & 1u))" in m
assert m.index("reset_status = fpga_spi_read_status();") < m.index("fpga_spi_reg_write(0x6Fu, 0xF0u);")
assert m.index("fpga_spi_reg_write(0x6Fu, 0xF0u);") < m.index("fpga_spi_reg_write(0x6B, 1);")
assert "AUDIOCFG PRE RST=%02X REL=%02X ARM=%u" in m
assert "fpga_spi_reg_write(0x6Fu, 0xF0u)" not in menu
assert "FPGA_SPI_REG_WRITE_CS_HOLD_US 3u" in spi
assert spi.count("bflb_mtimer_delay_us(FPGA_SPI_REG_WRITE_CS_HOLD_US);") == 2

print("PASS: M641 disk/reset preserved and A3 audio mode precedes slot commit")
print("Source check only: cross-compile and physical cold boot unverified")
