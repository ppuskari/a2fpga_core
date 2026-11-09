#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "fpga_spi.h"
#include "bflb_mtimer.h"
#include "ssi263_spi_bench.h"

static uint8_t local[256];
static uint64_t time_us=1000;
static int corrupt;
static int writes,reads;
uint64_t bflb_mtimer_get_time_us(void){return time_us;}
void fpga_spi_xfer_write(uint8_t space,uint32_t addr,const uint8_t *src,uint16_t len)
{
    assert(space==0&&addr==0&&len==256);
    memcpy(local,src,256);writes++;time_us+=220;
}
void fpga_spi_xfer_read(uint8_t space,uint32_t addr,uint8_t *dst,uint16_t len)
{
    assert(space==0&&addr==0&&len==256);
    memcpy(dst,local,256);
    if(corrupt)dst[0]^=1;
    reads++;time_us+=245;
}
int main(void)
{
    ssi263_spi_bench_result r=ssi263_spi_bench_run();
    assert(r.bytes_per_direction==16384);
    assert(r.mismatches==0);
    assert(r.write_elapsed_us==64*220);
    assert(r.read_elapsed_us==64*245);
    assert(r.write_bytes_per_sec>88200);
    assert(r.read_bytes_per_sec>88200);
    assert(writes==64&&reads==64);
    corrupt=1;
    r=ssi263_spi_bench_run();
    assert(r.mismatches==64);
    assert(writes==128&&reads==128);
    puts("PASS: P10 SPI benchmark mock transfer, rate accounting and corruption detection");
    return 0;
}
