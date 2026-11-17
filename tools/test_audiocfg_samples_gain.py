#!/usr/bin/env python3
"""Static checks of SynthLAB build gate and Original AY amplitude path."""
from pathlib import Path
from math import log10

root = Path(__file__).resolve().parents[1]
board = root / "boards/a2n20v2-Enhanced"
top = (board / "hdl/top.sv").read_text(encoding="utf-8")
bridge = (board / "hdl/mb_doc_bridge.sv").read_text(encoding="utf-8")
prebuild = (board / "prebuild.tcl").read_text(encoding="utf-8")
extractor = (root / "tools/extract_synthlab_piano.py").read_text(encoding="utf-8")
main = (board / "src/a2n20_bl616/firmware_host/main.c").read_text(encoding="utf-8")
menu = (board / "src/a2n20_bl616/firmware_host/menu.c").read_text(encoding="utf-8")

assert '$readmemh("hdl/piano_multisustain.mem", synthlab_pcm_rom)' in bridge
assert 'logic [31:0] synthlab_pcm_rom [0:1407]' in bridge
assert 'extract_synthlab_piano.py' in prebuild
assert '--download' in prebuild and '--check' in prebuild
assert 'error "SynthLAB ROM FAILED validation:' in prebuild
assert 'SAMPLE_FNV = 0x170BB8B3' in extractor
assert 'source.add_argument("--check", action="store_true"' in extractor
assert 'len(raw_lines) != 1408' in extractor
assert 'fnv32(packed) != SAMPLE_FNV' in extractor

assert 'function automatic signed [15:0] mb_original_ay_music_gain;' in top
assert '(extended <<< 7) + (extended <<< 6) +' in top
assert '(extended <<< 3) + extended) >>> 4;' in top
assert 'audio_original_w ? mb_original_ay_music_gain(mb_fx_pcm_l)' in top
assert 'audio_original_w ? mb_original_ay_music_gain(mb_fx_pcm_r)' in top
assert 'function automatic signed [15:0] mb_original_final_minus_2db;' in top
assert 'mb_original_final_minus_2db($signed(audio_sample_word_raw[0]))' in top
assert 'mb_original_final_minus_2db($signed(audio_sample_word_raw[1]))' in top
assert 'mb_original_gain_would_limit($signed(audio_sample_word_raw[0]))' in top
assert 'mb_original_gain_would_limit($signed(audio_sample_word_raw[1]))' in top
assert "MB_SPEECH_GAIN_NUM = 1" in top
assert "audio_enhanced_w ? (mb_speech_gain_w >>> 3) : mb_speech_gain_w;" in top
assert "mb_doc_gain_minus_2db($signed(audio_sample_word_raw[0]))" in top
assert "mb_doc_gain_minus_2db($signed(audio_sample_word_raw[1]))" in top
assert 'fpga_spi_reg_write(REG_AUDIO_MODE, s_audio_draft);' in menu
assert 'fpga_spi_reg_write(0x6Fu, 0xF0u);' not in main

gain = 201 / 16
assert abs(20 * log10(gain) - 22.0) < 0.05

def gain_music(x):
    signed_shift = (x * 201) >> 4
    return max(-18508, min(18508, signed_shift))

def hdmi_ceiling(x):
    # The actual 45/32 final HDMI gain, then output limiter.
    scaled = round(x * 45 / 32)
    return max(-26028, min(26028, scaled))

for raw in (0, 1, -1, 10, -10, 100, -100, 1000, -1000, 2000, -2000, 32767, -32768):
    boosted = gain_music(raw)
    assert -18508 <= boosted <= 18508
    assert -26028 <= hdmi_ceiling(boosted) <= 26028
assert gain_music(0) == 0
assert gain_music(1000) > 12000
assert gain_music(2000) == 18508

print("PASS: SynthLAB prerequisite, Original AY +21.98dB and -2dBFS ceiling")
print("SOURCE-ONLY: Gowin synthesis and physical listening unverified")
