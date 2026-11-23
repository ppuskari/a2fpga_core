cmake_minimum_required(VERSION 3.15)

include(proj.conf)

find_package(bouffalo_sdk REQUIRED HINTS $ENV{BL_SDK_BASE})

# Pull in shared FPGA-SPI sources from the FT2232 firmware (../firmware) so we
# do not duplicate them. Only fpga_spi/fpga_screen are reused; the device-mode
# (FTDI/JTAG/UART/CLI) sources are intentionally excluded from the host build.
sdk_add_include_directories(. ../firmware ../../../../../reference/ssi263/pico-v1.0.1)
# lwIP base config (SDK's reference lwipopts.h).
sdk_add_include_directories($ENV{BL_SDK_BASE}/components/net/lwip/lwip/lwip-port/config)
# CRITICAL: the SDK lwipopts defaults PBUF_POOL_SIZE to 0 unless CFG_ETHERNET_ENABLE
# is defined, which makes pbuf_alloc(PBUF_POOL) fail for EVERY received frame
# (USB-Ethernet RX silently dropped -> no DHCP). Give it an Ethernet-sized pbuf
# pool. (lwipopts uses #if !defined / #ifndef, so these compile defs win.)
sdk_add_compile_definitions(-DPBUF_POOL_SIZE=16 -DPBUF_POOL_BUFSIZE=1600)
# Multi-threaded SPI access (overlay writers + W5100 bridge task) -> enable the
# FreeRTOS mutex in the shared fpga_spi.c. The device build omits this (no FreeRTOS).
sdk_add_compile_definitions(-DFPGA_SPI_THREADSAFE)
# J2R9 MCU-only MOD SPI acceleration; no FPGA bitstream changes.
# Change to 0 in a separate local source checkout for known-good bytewise A/B.
# Do NOT enable this for the non-host/device-mode build.
set(FPGA_SPI_MOD_BULK_XFER 1 CACHE STRING "MOD SDRAM/PCM bulk SPI: 1=on 0=legacy")
if(NOT FPGA_SPI_MOD_BULK_XFER MATCHES "^[01]$")
    message(FATAL_ERROR "FPGA_SPI_MOD_BULK_XFER must be 0 or 1")
endif()
sdk_add_compile_definitions(-DFPGA_SPI_MOD_BULK_XFER=${FPGA_SPI_MOD_BULK_XFER})
# J2R9A physical safety default. Uninterrupted 512B SDRAM bursts failed the
# real J2R9 FPGA pattern sentinel readback. Do not enable on user hardware.
set(FPGA_SPI_MOD_BULK_SDRAM 0 CACHE STRING "0=proven bytewise SDRAM, 1=EXPERIMENTAL full-speed SDRAM")
if(NOT FPGA_SPI_MOD_BULK_SDRAM MATCHES "^[01]$")
    message(FATAL_ERROR "FPGA_SPI_MOD_BULK_SDRAM must be 0 or 1")
endif()
sdk_add_compile_definitions(-DFPGA_SPI_MOD_BULK_SDRAM=${FPGA_SPI_MOD_BULK_SDRAM})
# J2R9B: keep 8KiB total per-voice SRAM but fetch only 2KiB at a time.
# 4096 and 8192 allow controlled A/B builds with no source modification.
set(MOD_STORE_FETCH_BYTES 2048 CACHE STRING "Bytes per blocking sample SPI miss")
if(NOT MOD_STORE_FETCH_BYTES MATCHES "^(2048|4096|8192)$")
    message(FATAL_ERROR "MOD_STORE_FETCH_BYTES must be 2048, 4096 or 8192")
endif()
sdk_add_compile_definitions(-DMOD_STORE_FETCH_BYTES=${MOD_STORE_FETCH_BYTES})
# J2R10: speech/audio debug counters and periodic P10 console reports cost
# MCU cycles and shared FPGA-SPI OSD bandwidth even when MOD is playing.
# Preserve SSI speech engine, FIFO/error semantics and A3 mode selection.
set(SSI263_DIAG_COUNTERS 0 CACHE STRING "0=quiet SSI speech telemetry, 1=R10/R11 diagnostic reports")
if(NOT SSI263_DIAG_COUNTERS MATCHES "^[01]$")
    message(FATAL_ERROR "SSI263_DIAG_COUNTERS must be 0 or 1")
endif()
sdk_add_compile_definitions(-DSSI263_DIAG_COUNTERS=${SSI263_DIAG_COUNTERS})
# DIAGNOSTIC: intercept the SDK's exception_entry (it only printf's the fault to a
# UART we can't see) so __wrap_exception_entry can paint mcause/mepc on the overlay.
sdk_add_link_options(-Wl,--wrap=exception_entry)

# The host build routes FatFS disk_* between SD and USB in diskio_host.c, so
# sdmm.c must export its SD logic as mmc_disk_* instead of owning disk_*.
sdk_add_compile_definitions(-DFATFS_EXTERNAL_DISKIO)
# M3: autonomous FPGA 512-byte SD RX staging. Capability-gated at runtime:
# a newer MCU on an M2 FPGA silently uses the legacy bytewise SD tunnel.
# Bulk host SPI is independently A/B verified against the same FPGA buffer,
# disabling only the fast portal if 20MHz CDC causes any byte mismatch.
set(FPGA_SD_BURST_READ 1 CACHE STRING "0=all legacy SD bytes, 1=M3 FPGA-autonomous 512B SD RX")
set(FPGA_SPI_SD_BURST_PORTAL_BULK 1 CACHE STRING "0=bytewise XFER0, 1=fast 128-byte XFER0 frames with readback check")
set(FPGA_SD_BURST_VALIDATE_CRC 1 CACHE STRING "0=legacy discard SD read CRC, 1=verify every accelerated 512-byte sector CRC16")
foreach(flag FPGA_SD_BURST_READ FPGA_SPI_SD_BURST_PORTAL_BULK FPGA_SD_BURST_VALIDATE_CRC)
    if(NOT ${flag} MATCHES "^[01]$")
        message(FATAL_ERROR "${flag} must be 0 or 1")
    endif()
endforeach()
sdk_add_compile_definitions(-DFPGA_SD_BURST_READ=${FPGA_SD_BURST_READ})
sdk_add_compile_definitions(-DFPGA_SPI_SD_BURST_PORTAL_BULK=${FPGA_SPI_SD_BURST_PORTAL_BULK})
sdk_add_compile_definitions(-DFPGA_SD_BURST_VALIDATE_CRC=${FPGA_SD_BURST_VALIDATE_CRC})

sdk_add_compile_definitions(-DHXCMOD_MAXCHANNELS=8)

target_sources(app PRIVATE
    usbh_xinput.c
    usbh_hidinput.c
    ssi263_spi_bench.c
    ssi263_hybrid.c
    ../../../../../reference/ssi263/pico-v1.0.1/ssi263.c
    ../../../../../reference/ssi263/pico-v1.0.1/ssi263dsp.c
    w5100.c
    disk.c
    # Software ProTracker playback -> independent HDMI PCM (no DOC ownership).
    mcu_mod_audio.c
    mcu_hdmi_meter.c
    mcu_mod_gain.c
    mcu_mod_now_playing.c
    mcu_mod_jukebox.c
    mcu_mod_format.c
    mcu_mod_sample_store.c
    mcu_mod_pattern_store.c
    media_mailbox.c
    third_party/hxcmod/hxcmod.c
    diskio_host.c
    osd_console.c
    settings.c
    menu.c
    fwupdate.c
    fpga_jtag.c
    fpgaupdate.c
    telnetd.c
    sscbridge.c
    ftpd.c
    boot_timeline.c
    ../firmware/gcr_dsk.c
    ../firmware/fpga_spi.c
    ../firmware/fpga_screen.c
    # Disk II image serving: FatFS + SD-over-FPGA-SPI-tunnel (same set the FT2232
    # build compiles; diskio.c is intentionally excluded -- diskio_host.c provides
    # the FatFS disk_* router that dispatches to SD (sdmm.c) or USB (usbh_msc)).
    ../firmware/sdmm.c
    ../firmware/ff.c
    ../firmware/ffunicode.c
    ../firmware/fpga_sd.c
)
# P10-R4: BL616 has efficient single-precision FPU operations. The Pico
# reference declares 'real' as float, but unsuffixed C literals promote many
# expressions to double (software emulation on RV32IMAF). Keep reference data
# intact and only change literal evaluation for the 2 isolated Pico sources.
# Host PCM parity: correlation=0.999998, SNR=55.16 dB / 12288 samples.
# Do not apply -ffast-math globally or alter DOC/mockingboard code.
set_source_files_properties(
    ../../../../../reference/ssi263/pico-v1.0.1/ssi263.c
    ../../../../../reference/ssi263/pico-v1.0.1/ssi263dsp.c
    PROPERTIES COMPILE_OPTIONS "-O3;-fsingle-precision-constant"
)
# R10 Enhanced-only: R8 fast voiced noise and carrierless digital output.
# The original
# (unoptimized) Pico reference remains the default for other platforms.
# 512-point cosine LUT eliminates per-filter-tick libm cos calls.
# Omitting the artificial low-level carrier affects only this Enhanced build.
# CI compares unmodified/optimized 22.05kHz PCM before rollout.
set_source_files_properties(
    ../../../../../reference/ssi263/pico-v1.0.1/ssi263.c
    PROPERTIES COMPILE_DEFINITIONS "SSI263_R8_FAST_SWELL=1;SSI263_DIGITAL_NO_CARRIER=1"
)
target_link_libraries(app m)
sdk_set_main_file(main.c)

project(a2n20_bl616_host)
