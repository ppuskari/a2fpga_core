#!/usr/bin/env python3
"""Guard M2 console's O(page_size) cached pagination.

BL616 SD/FatFS scanning a 500-file directory can take seconds, so
previous/next must NEVER start a new disk_list_begin or wait for a scan.
Folder entry/parent navigation still require refreshing the correct catalog.
"""
from pathlib import Path

src = (Path(__file__).resolve().parents[1] / "src/a2n20_bl616/firmware_host/menu.c").read_text()

def between(begin: str, end: str) -> str:
    assert src.count(begin) == 1, f"missing/ambiguous {begin!r}"
    assert src.count(end) >= 1, f"missing {end!r}"
    return src.split(begin, 1)[1].split(end, 1)[0]

full = between("static void picker_load(void)\n", "static void picker_page_from_snapshot(void)\n")
assert "disk_list_begin(s_pick_path, s_pick_exts)" in full
assert "disk_list_poll_page(" in full
assert "waited < 15000" in full

cached = between("static void picker_page_from_snapshot(void)\n", "static void picker_choose(int id)\n")
assert "disk_list_poll_page(" in cached, "next page should copy from existing catalog"
assert "s_pick_page*MOD_PICK_PAGE_SIZE" in cached
assert "disk_list_begin(" not in cached, "next page must not reread FAT"
assert "usb_osal_msleep" not in cached, "next page must not block waiting for SD"
assert "picker_load();" in cached, "recover if another request invalidates snapshot"

actions = between("static void picker_choose(int id)\n", "static void picker_build(void)\n")
pages = actions.split("if(s_pick_mod && (id == -6 || id == -7)) {", 1)[1].split("if (id == -3)", 1)[0]
assert "picker_page_from_snapshot();" in pages
assert "if(s_pick_fs_error==0)" in pages
assert "picker_load();" in pages, "fallback on error must still refresh catalog"
assert "screen_refresh();" in pages

parent = actions.split("if (id == -3) {", 1)[1].split("if (id >= 0", 1)[0]
assert "picker_load();" in parent, "parent folder must rescan"
children = actions.split("if (id >= 0", 1)[1].split("if (s_pick_fw ||", 1)[0]
assert "picker_load();" in children, "entering a new folder must rescan"

print("PASS MCU M2: previous/next page copies 48 cached entries; folder changes rescan")
