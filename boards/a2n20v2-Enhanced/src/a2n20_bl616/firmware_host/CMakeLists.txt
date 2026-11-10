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
# DIAGNOSTIC: intercept the SDK's exception_entry (it only printf's the fault to a
# UART we can't see) so __wrap_exception_entry can paint mcause/mepc on the overlay.
sdk_add_link_options(-Wl,--wrap=exception_entry)

# The host build routes FatFS disk_* between SD and USB in diskio_host.c, so
# sdmm.c must export its SD logic as mmc_disk_* instead of owning disk_*.
sdk_add_compile_definitions(-DFATFS_EXTERNAL_DISKIO)

target_sources(app PRIVATE
    usbh_xinput.c
    usbh_hidinput.c
    ssi263_spi_bench.c
    ssi263_hybrid.c
    ../../../../../reference/ssi263/pico-v1.0.1/ssi263.c
    ../../../../../reference/ssi263/pico-v1.0.1/ssi263dsp.c
    w5100.c
    disk.c
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
# R8 BL616-only voiced-noise oscillator experiment. The original
# (unoptimized) Pico reference remains the default for other platforms.
# 512-point cosine LUT eliminates per-filter-tick libm cos calls.
# CI compares unmodified/optimized 22.05kHz PCM before rollout.
set_source_files_properties(
    ../../../../../reference/ssi263/pico-v1.0.1/ssi263.c
    PROPERTIES COMPILE_DEFINITIONS "SSI263_R8_FAST_SWELL=1"
)
target_link_libraries(app m)
sdk_set_main_file(main.c)

project(a2n20_bl616_host)
