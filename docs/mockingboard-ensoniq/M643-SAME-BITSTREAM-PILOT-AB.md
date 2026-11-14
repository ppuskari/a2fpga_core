# M6.4.3 same-bitstream pilot A/B — audio-only dropouts

**Branch:** `petar/mb-doc-m643-pilot-ab-20261114`  
**Parent:** `petar/mb-doc-m642-audio-pilot-20261114`.

## Observation and hypothesis

During extended real Apple IIe Sugar Plum playback with M6.4.2, the 1002.27Hz right-channel `±256` (approximately -42.1dBFS peak) HDMI PCM pilot was present continuously and no audio dropouts were heard. Earlier M6.4.1 music without a pilot exhibited variable-position 0.9–1.02-second *digital-zero in BOTH stereo channels* while HDMI VIDEO remained stable. Gowin post-route setup/hold passed. This is strongly consistent with a **possible receiving-device/capture-chain silence gate, autosquelch, or audio decoder relock**, but *could also be a placement-dependent FPGA change*. The original dropout mechanism is not proven.

The RTL `hdl/hdmi/packet_picker.sv` does not intentionally omit audio sample packets for zero-valued PCM: its send decision depends on the sample buffer readiness rather than sample amplitude.

## Change

Use the **existing S2 hardware pushbutton** (currently toggles a compile-time-disabled video overlay latch) to switch the right-channel diagnostic pilot **on/off at runtime**. The pilot clock advances continuously at 44.1kHz irrespective of output enable. Its boolean enable begins ON after reset, toggles at the debounced S2 rising edge in the 54MHz logic domain and crosses to the pixel/44.1kHz domain via a 2-register synchronizer.

- Both states have identical synthesized logic, placement, clocks, RAM, DOC, HDMI packetizer, R11 speech and BL616 firmware.
- Pilot ON: a 1002.27Hz, -42.1dBFS peak right-channel square wave is summed **after** the existing final limiter and reclamped at ±26028.
- Pilot OFF: exact original post-limiter right PCM; left unchanged in both states.
- Native AY FX whole-chip bypass OFF, coherent register publication ON, M6.4 de-click ON, debug overlay synthesized out.
- Unlike switching the M6.4.2 synthesis parameter, this experiment does not cause two different place-and-route solutions.
- The pulse may produce a small click when S2 changes state; do not misclassify that as a song artifact.

## Single-line Windows PowerShell steps

```powershell
git clone --single-branch --branch petar/mb-doc-m643-pilot-ab-20261114 https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-m643
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-m643
```

```powershell
py -3 tools\extract_synthlab_piano.py --download
```

Gowin project: `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj`. **FPGA-only build**; inspect physical STA and preserve known-good M6.4.2 bitstream. Do not reflash BL616.

## Controlled hardware A/B

1. With original HDMI/optical splitter, same Audacity gain/settings and same physical cables, start recording a 44.1 kHz stereo WAV.
2. After power-on pilot defaults ON. Play Sugar Plum for at least three repeats (~2 minutes). Confirm the continuous ~1kHz right-channel pilot.
3. Press **S2 once**. Pilot should disappear from right-channel spectrogram/quiet passages but music should continue. Continue for at least 3–4 song repeats.
4. If 0.9–1.02s digital-zero dropouts recur, **do not stop the recording**. Note their times. Press S2 again to restore pilot and play another 3–4 repeats.
5. Try a second ON/OFF cycle if needed and verify the video never loses sync.

### Interpretation

- Dropouts occur **only with pilot OFF**, and disappear when turned back ON *within the same FPGA bitstream*: compelling evidence for a downstream silence gate, audio receiver, splitter or capture-chain behavior tied to nonzero PCM. Inspect splitter/capture configuration and thresholds. Exact device identification still unproven.
- Dropouts occur during **both** pilot states, but pilot stays present while music is missing: upstream music/DOC/transfer/cross-domain data problem.
- Dropouts occur during **both** pilot states and the pilot disappears at the same time: HDMI packet/capture/transport problem.
- Dropouts never happen in either pilot state: inconclusive; change from M6.4.1 to M6.4.2/M6.4.3 placement or intermittent environmental issue remains possible.
- Pilot did not toggle: do not interpret A/B; verify S2 pushbutton and branch flashed before recording.

## Tests

`tests/mb_doc/tb_mb_hdmi_audio_pilot.sv` includes exact right PCM passthrough with pilot disabled, ON/OFF/ON switching, positive/negative limiter, no changes to left PCM, 44.1kHz pilot phase and sample-tick clock independence. `m643` GitHub workflow also runs M6, M6.4 and M6.4.1 simulated regressions. These are not Gowin STA and do not prove receiver behavior.

## Next work

If external receiver muting is confirmed, the long-term fix should be in the HDMI sink/splitter or an explicitly controlled minimal dither/pilot, not a spurious DOC restart or timing change. If placement-dependent, collect comparative Gowin timing/critical paths. Preserve the strong musical improvements from M6.4.1 (coherent register publication, reduced clicks, corrected apparent tuning) before M6.5 FX work.
