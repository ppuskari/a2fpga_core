# SenseiPlay8 P2Z — NTP selection freeze recovery (MCU only)

**Status:** P2Z defensive regression hotfix. Hardware root cause unconfirmed.
P2Y on hardware was reported to produce no sound and freeze the MCU menu
after selection of an NTP song. Portable P2Y CI was green; do **not**
assume this means hardware was stable.

## Candidate root cause and fix

The `sensei` worker ran on a 3,072-byte FreeRTOS stack, while P2Y kept both
`sensei_mod_player_t` and `sensei_ntp_player_t` in its task frame. NTP
file load nests `sensei_runtime_load()` (two decoder structs plus filesystem
request) into `sensei_ntp_import()` (64 instrument descriptors, 256-byte
page occupancy, and instrument map). Adding another native player state
may overflow the task stack in this call chain.

P2Z changes only MCU C sources:
- `tracker_state` becomes single-task static BSS, not automatic stack.
- Decoder state in `sensei_runtime_load()` becomes static BSS.
- Importer scratch in `sensei_ntp_import()` becomes static BSS.
  **Importer is not reentrant**; only the serialized Sensei worker calls it.
- Sensei task stack grows from 3,072 to 4,096 bytes.
- OSD console logs load stage, PCM size and DMA verification.
- GitHub CI includes `-fstack-usage` regression: worker + loader + importer
  must stay within conservative per-frame and cumulative budgets.

This is a **candidate fix**, not proof of the physical failure.
No `doc5503.sv`, FPGA transport, DOC sample bank, menu picker,
or NTP effect-engine behavior is changed in P2Z.

## Windows PowerShell 5.1 (paste each line separately)

### 1. Isolated P2Z source checkout

```powershell
$hw = 'C:\AppleIIgsDev_02\a2fpga-sensei-p2z'
if (-not (Test-Path "$hw\.git")) { git clone --branch petar/sensei8-p2z-ntp-stack-safety-20261120 --single-branch https://github.com/ppuskari/a2fpga_core.git $hw }
git -C $hw fetch origin petar/sensei8-p2z-ntp-stack-safety-20261120
git -C $hw switch petar/sensei8-p2z-ntp-stack-safety-20261120
git -C $hw pull --ff-only origin petar/sensei8-p2z-ntp-stack-safety-20261120
git -C $hw log -1 --oneline
```

### 2. FPGA/Gowin GUI

**No FPGA recompilation is necessary for P2Z.** It contains precisely the
same FPGA sources as P2Y. If the FPGA was power-cycled since the previous
P2Y SRAM programming, open this project's
`boards/a2n20v2-Enhanced/a2n20v2_enhanced.gprj` in Gowin GUI and
restore the P2Y bitstream to **SRAM only**, as for the earlier trial.
Keep golden FPGA flash untouched.

### 3. Audio assets

**No asset extraction is necessary for P2Z.** It only changes MCU runtime
stack/memory. Do not regenerate piano/voice memory files unless you are
actually rebuilding the FPGA.

### 4. Build MCU Stage 2

```powershell
if (-not $env:BL_SDK_BASE) { $env:BL_SDK_BASE = 'C:\AppleIIgsDev_02\bouffalo_sdk' }
Get-Item "$env:BL_SDK_BASE\project.build"
Get-Command make,riscv64-unknown-elf-gcc -ErrorAction Stop | Select-Object Name,Source
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host"
make -j4 CHIP=bl616 BOARD=bl616dk
if ($LASTEXITCODE -ne 0) { throw 'P2Z MCU build failed; do not flash' }
Get-Item .\build\build_out\a2n20_bl616_host_bl616.bin | Select-Object FullName,Length,LastWriteTime
Get-FileHash .\build\build_out\a2n20_bl616_host_bl616.bin -Algorithm SHA256
```

### 5. Stage 2 only, BL616 signed Stage 1 untouched

```powershell
Set-Location "$hw\boards\a2n20v2-Enhanced\src\a2n20_bl616"
py -3 .\tools\a2n20-mcu-program --detect
py -3 .\tools\a2n20-mcu-program --stage2 --firmware .\firmware_host\build\build_out\a2n20_bl616_host_bl616.bin --verify-flash
```

Never run `make flash`. Stage 1's signed region at 0x00000 must not
be touched; only application Stage 2 at 0x40000 is updatable.

## Acceptance

1. Restart with Native DOC mode and P2Y FPGA in SRAM.
2. Verify that the menu is navigable before selecting any song.
3. Select a **known working four-channel MOD** first; stop, browse again.
4. Select **15k.ntp**. Check that menu still responds and the MCU console
   reports `SENSEI P2Z: FAT FILE LOAD`, `SENSEI P2Z: PCM SIZE=...`,
   `SENSEI P2Z: DOC PCM DMA VERIFIED`, then
   `SENSEI P2Y: NTP V2 NATIVE C/FPGA`.
5. If the menu freezes again, record the **last** diagnostic line and any
   boot fault overlay. If the console reaches `DMA VERIFIED` before
   freezing, prioritize playback/SPI ownership analysis rather than
   the file-import stack.
6. Before judging effects, verify audio actually starts, STOP responds,
   and no diagnostic OVR counter increments.

Portable CI tests do not guarantee the full BL616 cross-build, SRAM
programming, or physical hardware playback.
