# J2R3: 1–8 channel HxCMOD .MODs + live PCM gain (test candidate)

## Source and rollback

- **Frozen hardware-working baseline:** branch
  `petar/mod-j2r2-4ch-hwpass-20261121`, exact commit
  `0ed365c12bc8b61f6c51a5e5812951954f483303`.
- **Experimental new version:** branch `petar/mod-j2r3-8ch-gain-20261121`.
- Build/flash MCU **Stage2 only** at BL616 flash offset `0x40000`.
  Keep signed Stage1 (`0x0`), saved audio A3 configuration and golden
  M1 FPGA bitstream intact.
- J2R3 changes MCU only: HxCMOD parser/capacity/cache, stereo postmix gain,
  and its menu controls. **No FPGA gateware changes.**

## Supported formats

J2R3 recognizes legacy HxCMOD MOD signatures `M.K.`, `M!K!`,
`M&K!`, `PATT`, `NSMS`, `LARD`, `FEST`, `FIST`, `N.T.` as
four-channel MODs, and `OKTA`, `OCTA` as eight-channel. It also recognizes
the HxCMOD's digit-mask families `$CHN`, `$$CH`, `$$CN`, `$$$C`,
`FLT$`, `EXO$`, `CD$1`, `TDZ$`, and `FA0$`, **only when the
decoded channel count is 1–8**. Examples: `4CHN`, `6CHN`, `8CHN`,
`FLT4`, `FLT8`, `EXO8`, `CD81`, `TDZ8`, and `FA08`.
Classic 15-instrument SoundTracker files are retained as four-channel.

- **Container:** standard `.MOD` only. `.XM`, `.S3M`, `.IT` are NOT
  enabled: HxCMOD has no decoder for those formats; adding their suffixes to
  the menu filter would not produce valid playback.
- **File size:** original 2 MiB whole-file ceiling retained.
- **Memory:** all patterns stay in MCU SRAM. Pattern allocation is
  `(max_pattern_index+1)*256*channels+header_size` bytes. An 8-channel
  128-pattern song needs ~257 KiB for patterns alone, and may correctly fail
  with "NO RAM" if MCU heap is too small. A future pattern cache could
  address that separately.
- **Samples:** full 2 MiB FPGA SDRAM region `0x400000..0x5FFFFF`.
  Eight independent 4-KiB read caches, up from four on J2R2.
- **8-channel sound correctness:** host tests compare HxCMOD direct-memory
  to FPGA SDRAM sample streams; they don't certify fidelity of every
  nonstandard tracker variant (e.g. FLT8) against an original tracker.
  Use known-good FastTracker 8CHN modules for initial physical tests.

## Adjustable gain, not on the FPGA HDL side

- **Default +8 dB**, live menu `PCM GAIN - LEFT/RIGHT`, choices
  0..12 dB in 1 dB steps. Default reapplies on MCU restart, not
  currently saved to flash.
- **Stereo-linked, block-peak protection at -2 dBFS sample peak** after
  HxCMOD but before SPI SPACE6; fixed-point, no audio-path float calls.
  Uses per-256-frame lookahead, fast attenuation and slow recovery.
  Because the limiter operates on sample peaks, do not interpret
  `-2 dBFS` as measured intersample/true-peak certification.
- The per-song limiter envelope resets when a new track successfully loads.

## Windows native build

Clone the new branch into a **separate folder**. Reuse the BL616 SDK,
GCC, and Make locations validated with J2R2 on your machine.

```powershell
$j2r3='C:\AppleIIgsDev_02\a2fpga-jukebox-j2r3'
git clone --branch petar/mod-j2r3-8ch-gain-20261121 --single-branch https://github.com/ppuskari/a2fpga_core.git $j2r3
$env:BL_SDK_BASE='C:\AppleIIgsDev_02\bouffalo_sdk'
$riscvBin='C:\AppleIIgsDev_02\bouffalo_tools\xuantie\xuantie-gcc-riscv-v2.10.2-windows-x86_64\bin'
$env:PATH="$env:BL_SDK_BASE\tools\make;$env:BL_SDK_BASE\tools\cmake\bin;$riscvBin;$env:PATH"
Set-Location "$j2r3\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host"
make -j4 CHIP=bl616 BOARD=bl616dk
if($LASTEXITCODE -ne 0){throw 'Build failure: do not flash'}
$bin=(Resolve-Path '.\build\build_out\a2n20_bl616_host_bl616.bin').Path
Get-Item $bin | Select FullName,Length,LastWriteTime
```

If and only if the native build succeeds, program **Stage2 only** with
the same verified tool used for J2R2:

```powershell
Set-Location "$j2r3\boards\a2n20v2-Enhanced\src\a2n20_bl616"
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware $bin --verify-flash
```

If power-cycling reverts the FPGA to an old flash image, reload your
known-good M1 FPGA bitstream into **volatile SRAM**, not FPGA flash.
No automatic FPGA/Stage1 flashing.

## Suggested staged physical test

1. Play known-good `101.mod` and `1minutedeadwaltz.mod` with +0 dB
   first, then +8 dB. Existing sample effects, speech and stereo balance
   should not change. Check gain LIVE with left/right. Compare HDMI
   output peaks at +8 dB; a louder MOD should be limited instead of
   hard-clipping above -2 dBFS sample peak.
2. Play `6CHN` MOD; verify all six voices audibly present and count
   reported as `6CH` in MCU MOD log.
3. Play `8CHN` MOD; test a long full-song passage with eight different
   instruments/voices. Check `UDR` in `MCU MOD: FRAMES=... FREE=... UDR=...`
   and measure menu response while playing.
4. Try `OKTA` and `OCTA` sources; then `FLT8` and other recognized
   signatures if files are available. Confirm no crashes or silent
   channel-loss.
5. Run the jukebox through mixed 4/6/8-channel MODs. NEXT/PREVIOUS,
   auto-advance, "NOW PLAYING" and track count should remain correct.
6. Leave `.XM`, `.S3M`, and `.IT` off SD's MOD playlist during this
   experiment; they cannot be decoded by HxCMOD.
7. If any crash, audio underrun spike or busy-loop occurs, restore
   the frozen J2R2 Stage2 MCU build without altering the golden FPGA
   bitstream. Share the exact MOD signature, size, and UART/console logs.

## CI coverage

- Original J1/J2 MOD file scanning, 1 MiB SDRAM sample parity and J2R2
  concurrent NOW PLAYING tests.
- J2R3 4/6/8-channel format and external SDRAM PCM parity matrix.
- J2R3 live 0..12 dB gain and sample-peak-limiter regression.
- M1 slot3, HDMI stereo FIFO, and native IIgs Ensoniq DOC RTL regressions.
- Native Bouffalo SDK cross-compile and **actual 8-channel MCU real-time
  performance** remain hardware/host-environment validation requirements.
