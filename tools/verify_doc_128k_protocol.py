#!/usr/bin/env python3
"""Behavioral and source audit for the A2FPGA DOC 128K protocol v1."""

from dataclasses import dataclass
from pathlib import Path


KEY_WRITES = (
    (0xE2, 0x41),
    (0xE3, 0x32),
    (0xE4, 0x46),
    (0xE5, 0x50),
)


@dataclass
class ProtocolModel:
    extension_enabled: bool = True
    unlocked: bool = False
    bank1_loaded: bool = False
    key_state: int = 0

    def reset(self) -> None:
        self.unlocked = False
        self.bank1_loaded = False
        self.key_state = 0

    @property
    def status(self) -> int:
        if not self.extension_enabled:
            return 0x00
        return 0x10 | (int(self.bank1_loaded) << 1) | int(self.unlocked)

    def doc_write(self, address: int, data: int) -> None:
        address &= 0xFF
        data &= 0xFF

        if not self.extension_enabled or not 0xE2 <= address <= 0xE6:
            self.key_state = 0
            return

        if self.key_state < len(KEY_WRITES):
            if (address, data) == KEY_WRITES[self.key_state]:
                self.key_state += 1
            else:
                self.key_state = 0
            return

        self.key_state = 0
        if address != 0xE6:
            return
        if data == 0x01:
            self.unlocked = True
            self.bank1_loaded = False
        elif data == 0x00:
            self.unlocked = False
            self.bank1_loaded = False

    def command(self, value: int) -> None:
        for address, data in KEY_WRITES:
            self.doc_write(address, data)
        self.doc_write(0xE6, value)

    def upload_bank(self, sound_control: int) -> int:
        bank = int(self.unlocked and bool(sound_control & 0x10))
        if bank:
            self.bank1_loaded = True
        self.key_state = 0
        return bank

    def playback_bank(self, rts: int) -> int:
        return int(self.unlocked and self.bank1_loaded and bool(rts & 0x40))


def check_behavior() -> None:
    model = ProtocolModel()
    assert model.status == 0x10

    # Music Studio's $35/$75 templates must remain strict 64K behavior.
    assert model.upload_bank(0x75) == 0
    assert model.playback_bank(0x7F) == 0
    assert model.status == 0x10

    # A damaged or interrupted key must not unlock.
    model.doc_write(0xE2, 0x41)
    model.doc_write(0xE3, 0x33)
    model.doc_write(0xE4, 0x46)
    model.doc_write(0xE5, 0x50)
    model.doc_write(0xE6, 0x01)
    assert model.status == 0x10

    model.command(0x01)
    assert model.status == 0x11
    assert model.upload_bank(0x60) == 0
    assert model.status == 0x11
    assert model.playback_bank(0x7F) == 0

    assert model.upload_bank(0x70) == 1
    assert model.status == 0x13
    assert model.playback_bank(0x3F) == 0
    assert model.playback_bank(0x7F) == 1

    model.command(0x00)
    assert model.status == 0x10
    assert model.upload_bank(0x75) == 0
    assert model.playback_bank(0x7F) == 0

    model.command(0x01)
    model.upload_bank(0x70)
    model.reset()
    assert model.status == 0x10
    assert model.playback_bank(0x7F) == 0


def check_source() -> None:
    root = Path(__file__).resolve().parents[1]
    glu = (root / "hdl/sound/sound_glu.sv").read_text(encoding="utf-8")
    top = (
        root / "boards/a2n20v2-Enhanced/hdl/top.sv"
    ).read_text(encoding="utf-8")

    required_glu = (
        "parameter bit ENABLE_128K_EXTENSION = 1'b0",
        "EXT_KEY_DATA_0 = 8'h41",
        "EXT_KEY_DATA_1 = 8'h32",
        "EXT_KEY_DATA_2 = 8'h46",
        "EXT_KEY_DATA_3 = 8'h50",
        "EXT_COMMAND_LOCK = 8'h00",
        "EXT_COMMAND_UNLOCK = 8'h01",
        "sound_128k_unlocked_r && sound_control_r[4]",
        "sound_128k_unlocked_r &&",
        "sound_128k_enable_r &&",
    )
    for text in required_glu:
        assert text in glu, f"missing HDL protocol element: {text}"

    assert "FORCE_LEGACY_64K" not in glu
    assert ".ENABLE_128K_EXTENSION(1'b1)" in top
    assert "doc_128k_status_w" in top


def main() -> None:
    check_behavior()
    check_source()
    print("DOC 128K protocol v1 verification passed.")


if __name__ == "__main__":
    main()

