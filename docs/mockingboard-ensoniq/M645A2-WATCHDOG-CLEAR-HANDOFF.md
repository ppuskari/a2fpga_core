# M6.4.5a2 — Corrected sample-strobe watchdog

**Branch:** `petar/mb-doc-m645a2-watchdog-clear-20261115` (based on M6.4.5a)  
**Date:** 2026-11-15  
**Status:** RTL/CI diagnostics; Gowin PnR and hardware validation required.

## Hardware observation

With M6.4.5a loaded, user saw leftmost LED heartbeat blinking normally, while second LED from left (LED3) stayed illuminated regardless of S2. Direct HDMI to LCD improved video and sound relative to the external HDMI splitter/optical extractor chain; video and audio were still not fully proven stable. Therefore there may be two separate issues: the external signal chain, and a latched strobe watchdog event.

## Actual M6.4.5a bug

`mb_audio_strobe_watch.sv` had two nonblocking assignments to `stalled_o` from the same `always` block, first clearing and later setting it. With a saturated timeout the later `stalled_o<=1` overrode S2 clear. The elapsed-time count wasn't reset on S2 clear, either. `top.sv` also used the *level* of S2 as clear; the button's idle polarity could mask/retain errors.

## Changes

- Make S2 clear a high-priority branch, resetting **both** `stalled_o` and `since_tick_r`.
- After clear, any continuing absence of audio ticks relatches only after a fresh 2 ms timeout at 27 MHz.
- Sample-tick heartbeat continues independently of clear.
- Use two-FF synchronization of the debounced S2 **level** and compare to the previous pixel-clock value. Either S2 press or release edge emits a one-clock clear pulse; holding S2 does not mask faults.
- LED4 leftmost toggles every 0.5 second (one full 1Hz flash). **LED3 second from left is active-low electrically; lit means the fault latch was set.** LED2-0 retain memory/video indications.
- The testbench now tests clearing during an active saturated timeout, a subsequent relatch on genuinely absent pulses, and return to regular pulses without false faults.
- No DOC, piano, SSI263, BL616, HDMI packetizer, PLL, audio_timing, 44.1kHz stream or video overlay changes. Native AY FX bypass remains off.

## Windows PowerShell 5.1 checkout

```powershell
git clone --single-branch --branch petar/mb-doc-m645a2-watchdog-clear-20261115 https://github.com/ppuskari/a2fpga_core.git C:\AppleIIgsDev_02\a2fpga-mb-doc-m645a2
```
```powershell
Set-Location C:\AppleIIgsDev_02\a2fpga-mb-doc-m645a2
```
```powershell
py -3 tools\extract_synthlab_piano.py --download
```

Open `boards\a2n20v2-Enhanced\a2n20v2_enhanced.gprj`. FPGA only after successful physical PnR and timing. Keep original M6.4.3 working bitstream available.

## Hardware checks

1. **First bypass HDMI extractor and splitter:** direct Tang Nano → LCD with known-good HDMI cable. Check video and built-in speaker audio for three Sugar Plum cycles. Do not use a questionable splitter as the measuring path.
2. Press/release S2 after startup and verify LED3 clears, provided the strobe is currently active. LED4 should continue its 1Hz blinking. Note any relatching of LED3 **without** touching S2.
3. If video/audio glitches with LED3 still off, the 44.1kHz pulse generator didn't suffer a >=2ms pause *according to this monitor*: investigate HDMI packet buffering, source audio and physical link. If LED3 turns on, a missing-pulse event is indicated but **not necessarily simultaneous with the audio dropout**, since the latch persists.
4. Run M6.4.5b direct packet capture, M6.4.5d minimal strobe, and M6.4.5c upstream marker **only after** the physical HDMI link is stable.
5. If physical tests remain unstable, revert to M6.4.3 with its pilot OFF. Keep the WAVs and post-route reports.

### Caveats

The watchdog sees the `clk_audio_w` pulse in the pixel clock domain. It does not directly monitor whether PCM samples actually contain music or whether HDMI packets are accepted downstream. A heartbeat blinking normally proves regular sample pulse activity at the moment but does not exclude brief earlier interruptions. A missing pulse may be a consequence of a reset/PLL event; a static-timing pass alone cannot prove external HDMI signal integrity.
