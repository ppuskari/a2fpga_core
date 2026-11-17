#!/usr/bin/env python3
"""M641-safe AUDIOCFG boot/source checks. Not FPGA synthesis or MCU build.

Important: byte-for-byte M641 comparisons use raw Git bytes. Windows'
default Python text encoding (often cp1252) must NOT transcode the
non-ASCII Unicode characters in the original UTF-8 C source.
"""
from pathlib import Path
import hashlib
import subprocess
import sys

def canonical_git_bytes(data):
    """Normalize Windows checkout CRLF without decoding/re-encoding text."""
    return data.replace(bytes([13, 10]), bytes([10]))

def git_blob(data):
    data = canonical_git_bytes(data)
    return hashlib.sha1(("blob %d" % len(data)).encode("ascii") +
                        bytes([0]) + data).hexdigest()

if "--self-test" in sys.argv:
    original = "/* M641 — bridge → reset */\n".encode("utf-8")
    windows = original.replace(bytes([10]), bytes([13, 10]))
    assert original != windows
    assert canonical_git_bytes(windows) == original
    assert git_blob(windows) == git_blob(original)
    # This proves why default cp1252 read_text() followed by UTF-8 encode
    # was not byte-preserving on a Windows installation without UTF-8 mode.
    assert original.decode("cp1252").encode("utf-8") != original
    print("PASS: raw UTF-8 C bytes and Windows CRLF preservation")
    sys.exit(0)

ROOT = Path(__file__).resolve().parents[1]
B = ROOT / "boards" / "a2n20v2-Enhanced"
H = B / "src/a2n20_bl616/firmware_host"

# Read the main source as RAW BYTES, not through locale-sensitive read_text.
main_data = canonical_git_bytes((H / "main.c").read_bytes())
m = main_data.decode("utf-8")  # for ASCII source-pattern assertions only
d = (H / "disk.c").read_bytes()
menu = (H / "menu.c").read_text(encoding="utf-8")
settings_h = (H / "settings.h").read_text(encoding="utf-8")
settings_c = (H / "settings.c").read_text(encoding="utf-8")
spi = (B / "src/a2n20_bl616/firmware/fpga_spi.c").read_text(encoding="utf-8")

# The validated M641 physical boot and reset code must remain untouched.
assert git_blob(d) == "0e8a7b7c687a434077e78001e205e309f61d12ee", (
    "M641 disk.c differs from the baseline; inspect local modifications")

# Compare only raw bytes OUTSIDE the guarded audio transaction against
# the original M641 commit. This must work on Windows with core.autocrlf.
start_marker = b"    /* AUDIOCFG: M641 still owns"
end_marker = b"    /* Apply the persisted slot map EARLY"
start = main_data.index(start_marker)
end = main_data.index(end_marker, start)
current_without_audio = main_data[:start] + main_data[end:]
M641_COMMIT = "8af7df27156e1a95b5346b9851e20d69697786d8"
MAIN_PATH = "boards/a2n20v2-Enhanced/src/a2n20_bl616/firmware_host/main.c"
m641_main = canonical_git_bytes(subprocess.check_output(
    ["git", "show", f"{M641_COMMIT}:{MAIN_PATH}"], cwd=ROOT))

if current_without_audio != m641_main:
    import itertools
    offset = next((i for i, (a, b) in enumerate(
        itertools.zip_longest(current_without_audio, m641_main))
        if a != b), min(len(current_without_audio), len(m641_main)))
    line = current_without_audio[:offset].count(bytes([10])) + 1
    raise AssertionError(
        f"M641 main.c differs outside AUDIOCFG at byte {offset}, line {line}. "
        "Inspect: git diff -- boards/a2n20v2-Enhanced/src/a2n20_bl616/"
        "firmware_host/main.c")

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
assert 'AUD INIT RDY=%u A3=%u' in m

# The saved-mode selection MUST NOT depend on the old SDRAM-ready
# result: control registers are available independently of SDRAM status.
# An automatic F0 reset is forbidden, as it defeats physical Disk II boot.
audio_start = m.index("    /* AUDIOCFG: select persisted audio BEFORE")
audio_end = m.index("    /* Apply the persisted slot map EARLY", audio_start)
audio = m[audio_start:audio_end]
assert "if (ready)" not in audio
assert "for (int attempt = 0; attempt < 16 && !matched; ++attempt)" in audio
assert "fpga_spi_reg_read(0x6Fu)" in audio
assert "fpga_spi_reg_read(0x6Bu)" in audio
assert "fpga_spi_reg_write(0x6Fu, wanted);" in audio
assert "fpga_spi_reg_write(0x6Fu, 0xF0u);" not in m
assert "fpga_spi_reg_write(0x2E" not in m
assert "fpga_spi_reg_write(0x6Fu, 0xF0u);" not in menu
assert "fwupdate_request_restart();" in menu
assert "FPGA_SPI_REG_WRITE_CS_HOLD_US 3u" in spi
assert spi.count("bflb_mtimer_delay_us(FPGA_SPI_REG_WRITE_CS_HOLD_US);") == 2

print("PASS: M641 disk/reset preserved and A3 audio mode precedes slot commit")
print("Source check only: cross-compile and physical cold boot unverified")
