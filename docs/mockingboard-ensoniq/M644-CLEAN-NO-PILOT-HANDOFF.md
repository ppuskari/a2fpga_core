# M6.4.4 Clean Music — pilot-removed hardware A/B

**Branch:** `petar/mb-doc-m644-clean-no-pilot-20261114`  
**Parent:** M6.4.3 `petar/mb-doc-m643-pilot-ab-20261114` (successful hardware PCM recording with pilot ON and OFF).  
**HDL:** M6.4.1 byte-for-byte `top.sv` and Gowin project, with no pilot module instantiated and no S2 pilot toggle.

## Why

On M6.4.1 the stereo HDMI audio recording displayed intermittent ~one-second full-stereo digital silences, with stable HDMI video. M6.4.2 adding a quiet 1002Hz right-channel post-limiter audio pilot eliminated observed gaps; importantly, M6.4.3 **remained clean even with its pilot switched OFF using S2**. The coherent AY-to-DOC register publication improved Sugar Plum pitch consistency and M6.4 de-click removed several transient clicks. It is not established that the pilot tone itself cured the missing audio; synthesis placement or the intermittent receiving device may be relevant.

This new build **removes every M6.4.2/3 pilot source, port, parameter, right-channel mixer, and S2 pilot control**. The old video overlay module remains present in source but is compile-time disabled as before, and the legacy S2 overlay button logic has no active video effect. Nothing has been changed in the shared DOC core, SSI263/R11 speech path or BL616 firmware.

## Restored FPGA configuration

```systemverilog
parameter bit MB_DOC_FX_AY_BYPASS_ENABLE = 1'b0,
parameter bit MB_DOC_DECLICK_ENABLE = 1'b1,
parameter bit MB_DOC_COHERENT_PUBLISH_ENABLE = 1'b1,
```

`DebugOverlay.ENABLE(1'b0)` remains disabled. The `audio_sample_word[0]` and `audio_sample_word[1]` connections return directly to the original gain/limit functions, with no pilot or synthetic PCM downstream.

### Caution about the A/B conclusion

This is a **reproducibility check**, not a further DSP correction. Because the synthesis HDL and Gowin project are identical to M6.4.1, the place-and-route tool may produce the same or very similar implementation and potentially the same failure. A clean run would mean the original failure was not reproduced, **not that any particular mechanism was disproven**. Preserve the M6.4.3 pilot-capable stable FPGA bitstream and its captured WAV for rollback and comparison.

## PowerShell 5.1 — one-line commands

```powershell
git clone --single-branch --branch petar/mb-doc-m644-clean-no-pilot-20261114 https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-m644
```

```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-m644
```

```powershell
py -3 tools\extract_synthlab_piano.py --download
```

Gowin project: `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj`. **FPGA only; no BL616 reflash.** Save and compare both post-route STA and, if practical, the implementation's output hash before changing hardware.

## Hardware validation

1. Verify there is **no 1002Hz right-channel pilot** at startup or while playback is stopped. S2 no longer controls any pilot.
2. Record Sugar Plum for at least **5 repeats** (~3m10s), including the ~38.16s loop boundaries. Keep output gain, cables, recording path and audio device settings unchanged from the M6.4.3 run.
3. Check for unexpected ~1-second digital-zero gaps in active music, note attacks that disappear, detuning, and clicks at the song repeat. Check HDMI picture synchronization separately.
4. Test MINUET, WEASEL, rapid KEYBOARD repeats and a longer 15–20 minute soak.
5. If any dropout reappears, preserve exact WAV/position, M6.4.4 bitstream and Gowin STA, then revert to the saved M6.4.3 bitstream. If clean, keep both bitstreams as comparison candidates rather than declaring the original intermittent issue permanently solved.

## Automated tests

`.github/workflows/mb-doc-m644-clean.yml` checks that no pilot module or S2 pilot control exists, then runs M6, M6.4 and M6.4.1 Icarus test suites for DOC settings 0/1/2. Software-level regression does not replace physical FPGA timing and audio stability testing.

After hardware validation we can freeze the best version and proceed to M6.5 sampled FX integration using DOC oscillators 6 and 7, without restoring native whole-chip AY output switching.
