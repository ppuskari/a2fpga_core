/*
 * P10 feasibility probe (opt-in, NOT the working SSI-263 audio transport).
 * Tests BL616 SPI0 byte-at-a-time XFER throughput against the existing
 * 256-byte local FPGA RAM (XFER SPACE 0) without modifying gateware.
 *
 * Call ONCE before starting FreeRTOS tasks. Does not quantify mutex
 * contention, USB traffic or 5/10/20ms transfer latency tails.
 */
#include "ssi263_spi_bench.h"
#include "fpga_spi.h"
#include "bflb_mtimer.h"

#define SIZE 256u
#define ROUNDS 64u
static uint8_t tx_buf[SIZE], rx_buf[SIZE];

static uint32_t throughput(unsigned bytes, uint64_t micros)
{
    if (!micros) return 0;
    return (uint32_t)(((uint64_t)bytes * 1000000u) / micros);
}

ssi263_spi_bench_result ssi263_spi_bench_run(void)
{
    ssi263_spi_bench_result out = {0};
    const unsigned byte_count = SIZE * ROUNDS;
    out.bytes_per_direction = byte_count;
    for (unsigned i=0;i<SIZE;i++)
        tx_buf[i]=(uint8_t)((i*73u+0x5Bu)&255u);

    /* Source is local RAM SPACE 0 and is not used by the disk or ROM
     * service, but benchmark only pre-scheduler to avoid collisions.
     * The 256-byte buffer wraps if addr exceeds 255, so use addr=0. */
    uint64_t begin = bflb_mtimer_get_time_us();
    for (unsigned r=0;r<ROUNDS;r++)
        fpga_spi_xfer_write(FPGA_SPACE_LOCAL,0,tx_buf,SIZE);
    uint64_t midpoint = bflb_mtimer_get_time_us();
    for (unsigned r=0;r<ROUNDS;r++) {
        fpga_spi_xfer_read(FPGA_SPACE_LOCAL,0,rx_buf,SIZE);
        for(unsigned i=0;i<SIZE;i++)
            if(rx_buf[i]!=tx_buf[i])out.mismatches++;
    }
    uint64_t end = bflb_mtimer_get_time_us();
    out.write_elapsed_us=(uint32_t)(midpoint-begin);
    out.read_elapsed_us=(uint32_t)(end-midpoint);
    out.write_bytes_per_sec=throughput(byte_count,midpoint-begin);
    out.read_bytes_per_sec=throughput(byte_count,end-midpoint);
    out.total_bytes_per_sec=throughput(byte_count*2u,end-begin);
    return out;
}
