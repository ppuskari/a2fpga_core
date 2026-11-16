# AUDIOCFG A1/A2 — Four-Mode MCU Boot Selector

Base: `petar/mb-doc-m641-coherent-20261113`. This is an isolated integration
branch, not a replacement for the M641 golden baseline or ongoing MB6.6 work.

## Scope

- MCU menu: `MAIN MENU > AUDIO CONFIG`, with Original Mockingboard,
  Enhanced DOC Mockingboard, Native DOC, and Shared mode choices.
- Settings: mode is one byte in former `reserved[0]` of the existing v3
  CRC-protected flash blob. Its size and all old field/CRC offsets are unchanged.
  Legacy flash defaults to Enhanced (0); no settings migration/erase required.
- Commit via explicit `SAVE FOR NEXT BOOT` only, avoiding repeated flash erases
  while cycling choices. A failed save restores the previous RAM mode.
- FPGA SPI register 0x6F: write 0..3; read returns 0xA0 | latched mode;
  other write values are rejected. Reset default = 0 (Enhanced).
- MCU writes and verifies 0x6F (up to five attempts) before the slot-map 0x6B
  strobe and the normal mount-driven 0x2E reset release. The M641 FPGA
  retains its existing standalone/timeout reset-release fallbacks. Older
  cores lack the signature and boot continues unchanged.
- Current FPGA top exports the selection wire without connecting it to the
  Mockingboard/Ensoniq/SSI paths. **No mode changes sound behavior in A1/A2.**
  Backend gating, native IIe Slot 4 DOC port, and shared oscillator allocation
  are A3 and later work.

## Physical validation checklist

1. Build and flash the Enhanced FPGA from this branch, then build/flash the
   matching `firmware_host` MCU binary (stage 2, usual established procedure).
   Do not overwrite the known-good M641 release artifacts.
2. On first boot, inspect OSD console for
   `AUDIOCFG A1/A2: REQ=0 ACK (NO ROUTING)` before Apple II startup.
   Check that the Apple II still boots and Slot 4 Mockingboard music/FX/speech
   match the baseline (no new dropout, timing, or keyboard issues).
3. Use USB keyboard TAB to open MCU menu, then ENTER to enter AUDIO CONFIG;
   verify default `ENHANCED MB`, `FLASH SAVED` and `FPGA BOOT REQUEST`
   both Enhanced.
4. Cycle through all four choices with LEFT/RIGHT. The asterisk (*) beside
   SAVE denotes an action, not an already saved choice. For a USB keyboard,
   A/B labels refer to gamepad buttons: ENTER = OK, ESC = BACK. Press DOWN
   to highlight `SAVE FOR NEXT BOOT (ENTER)`, then ENTER to commit. Before
   saving, `FLASH SAVED` and FPGA boot request must not change. Re-open the
   screen and confirm `FLASH SAVED` updates, while `FPGA BOOT REQUEST`
   remains the prior boot value.
5. Cold power-cycle. For each mode, confirm console `REQ=N ACK`, FPGA readback
   matches the saved mode, and all M641 audio behavior remains unchanged.
6. After each reboot check USB keyboard TAB responsiveness, MCU console
   switching, disk mounts, ProDOS boot, and no impact on MB/SSI263/Ensoniq.
7. Optional compatibility test: use an older FPGA with the updated MCU.
   Expect `NO A2 CORE` / `UNAVAILABLE`, never an assertion that routing changed.
8. Finally restore Enhanced (0) and power-cycle before returning to ongoing
   MB6.6 validation.

## Acceptance

- Four choices render and can be selected and committed.
- Flash settings remain valid across reboot; existing boot/storage/network
  settings are preserved.
- FPGA 0x6F acknowledges and reports requested selection.
- Audio mode handshake occurs before slot reconfiguration (0x6B), and before
  the normal mount-driven reset release (0x2E). The M641 reset-hold circuit
  also has an independent timeout backstop, so this is not a hard boot gate.
- Existing M641 audio remains bit-equivalent in routing; original/Native/Shared
  **do not yet change synthesis**, and no native IIe DOC register map exists.
- Report separately: source inspection, FPGA/MCU build results, and physical
  hardware testing. Neither build nor hardware validation is implied by commit.
