# DOC and HDMI Clipping History Overlay

The Enhanced-board debug overlay shows four live clipping histories without
changing the audio path, DOC headroom, or HDMI gain. Each field contains eight
time slices. One slice covers 125 ms, so the full field covers one second.

The leftmost bit is the oldest slice and the rightmost bit is the newest. A bit
is `1` when at least one audio sample clipped during that slice.

| Overlay row | Field | Signal |
|---|---:|---|
| Top | 2 | DOC left completed mix |
| Top | 3 | DOC right completed mix |
| Bottom | 2 | DOC mono completed mix |
| Bottom | 3 | HDMI post-gain, either channel |

The four existing oscillator-HALT fields remain in fields 0 and 1 of each row.
The existing hexadecimal DOC saturation byte also remains unchanged; its high
nibble is sticky until reset, while these histories scroll continuously.

## Reading the display

- `00000001`: a clip occurred in the newest 125 ms slice.
- `00010000`: the clip is about half a second old.
- Sparse moving `1` bits: brief transient limiting.
- Several adjacent `1` bits: recurring clipping.
- `11111111`: clipping occurred in every slice during the last second.

DOC history events are sampled only when a full left/right/mono mix completes.
The HDMI history is sampled on the 44.1 kHz audio strobe and is set when either
channel would exceed signed 16-bit range after the unchanged `45/32` gain.

## Implementation

- `hdl/sound/doc5503.sv` captures left, right, and mono histories.
- `hdl/sound/sound_glu.sv` routes the three history bytes.
- `boards/a2n20v2-Enhanced/hdl/top.sv` captures HDMI history and maps all four
  histories into the overlay.
- `hdl/debug/debugoverlay.sv` parameterizes the number of bit fields per row.
  Enhanced selects four; the default remains two for other boards.

The audio samples still use the existing saturating conversions. This feature
is diagnostic only.
