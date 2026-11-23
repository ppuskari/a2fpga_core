/* Compile the ACTUAL SD/FatFS block IO source with a fake FPGA SPI link.
 * Test 512B token->autonomous clocking->XFER read->CRC ordering, old-M2
 * hardware fallback, FPGA failure, timeout (never partial success) and
 * untouched 16B CSD reads.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
/* Include the repository's REAL FatFS typedefs: sdmm.c uses quoted
 * includes from its firmware directory, not the mock include path. */
#include "../src/a2n20_bl616/firmware/ff.h"
#include "../src/a2n20_bl616/firmware/diskio.h"
#include "fpga_spi.h"
#include "bflb_mtimer.h"
#define CHECK(c) do { if(!(c)){fprintf(stderr,"FAIL M3 FatFS line %d: %s\n",__LINE__,#c);exit(1);} } while(0)
static uint8_t card_stream[520],buffered[512];
static unsigned cursor,bytes_polled,burst_started,burst_aborted,portal_reads;
static bool m3_supported,force_error,force_timeout;
static bool waiting;
static unsigned status_count,scheduler_yields;
static uint64_t fake_us;
static uint8_t last_rx;
static unsigned osd_lines;
void osd_log(const char *fmt,...){(void)fmt;osd_lines++;}
void vTaskDelay(uint32_t ticks){scheduler_yields++;fake_us+=ticks*1000u;}
uint64_t bflb_mtimer_get_time_us(void){return fake_us;}
void bflb_mtimer_delay_us(uint32_t us){fake_us+=us;}
uint8_t fpga_spi_reg_read(uint8_t reg)
{
    if(reg==0x6D)return last_rx;
    CHECK(reg==0x6E);
    uint8_t result=m3_supported?0x80u:0u;
    if(waiting) {
        status_count++;
        if(force_timeout)return result|0x20u;
        if(status_count>2u) {
            result|=0x40u;
            if(force_error)result|=0x10u;
        } else result|=0x20u;
    }
    return result;
}
void fpga_spi_reg_write(uint8_t reg,uint8_t val)
{
    if(reg==0x6D) {
        (void)val;
        CHECK(cursor<sizeof card_stream);
        last_rx=card_stream[cursor++];
        bytes_polled++;
        return;
    }
    CHECK(reg==0x6E);
    if(val==0xA1) {
        burst_started++;
        CHECK(m3_supported && cursor==1u);
        memcpy(buffered,&card_stream[cursor],512u);
        cursor+=512u;
        status_count=0;
        waiting=true;
    } else if(val==0xAF) {
        burst_aborted++;
        waiting=false;
    } else CHECK(0);
}
void fpga_spi_sd_burst_buffer_read(uint8_t dest[512])
{
    CHECK(waiting && !force_timeout && !force_error);
    memcpy(dest,buffered,512u);
    portal_reads++;
    waiting=false;
}
bool fpga_spi_sd_burst_bulk_ok(void){return true;}

/* Other SPI API declarations are intentionally not needed by SD driver. */
#include "../src/a2n20_bl616/firmware/sdmm.c"

static void prepare(unsigned data_bytes,bool cap)
{
    CHECK(data_bytes+3u<=sizeof card_stream);
    m3_supported=cap;
    force_error=force_timeout=false;
    cursor=bytes_polled=burst_started=burst_aborted=portal_reads=0u;
    fake_us=0u;status_count=scheduler_yields=0u;waiting=false;
    card_stream[0]=0xFE;
    for(unsigned i=0;i<data_bytes;i++)
        card_stream[i+1u]=(uint8_t)(i*37u+((i>>4u)*7u)+0xA5u);
    const uint16_t crc=sd_m3_crc16(&card_stream[1],data_bytes);
    card_stream[data_bytes+1u]=(uint8_t)(crc>>8);
    card_stream[data_bytes+2u]=(uint8_t)crc;
    s_sd_burst_cap=-1;
}
static void check_bytes(const uint8_t *buf,unsigned n)
{
    CHECK(!memcmp(buf,&card_stream[1],n));
}
int main(void)
{
    uint8_t sector[512];
    CHECK(sd_m3_crc16((const BYTE *)"123456789",9u)==0x31C3u);
    prepare(512u,true);
    CHECK(rcvr_datablock(sector,512u)==1);
    check_bytes(sector,512u);
    CHECK(burst_started==1u && portal_reads==1u && burst_aborted==0u);
    CHECK(bytes_polled==3u && cursor==515u);
    CHECK(scheduler_yields>=2u);
    CHECK(mmc_sd_burst_read_count()>=1u);

    /* Same Stage2 must remain compatible with existing M2 FPGA hardware. */
    prepare(512u,false);
    CHECK(rcvr_datablock(sector,512u)==1);
    check_bytes(sector,512u);
    CHECK(burst_started==0u && portal_reads==0u && bytes_polled==515u);

    /* CSD and other short packets must NEVER use the 512-byte hardware. */
    prepare(16u,true);
    CHECK(rcvr_datablock(sector,16u)==1);
    check_bytes(sector,16u);
    CHECK(burst_started==0u && bytes_polled==19u);

    /* The XFER readback can be perfect while real SD->FPGA MISO data
     * was corrupted. A mismatched SD data CRC must reject the sector and
     * disable the M3 path until the next card initialization. */
    prepare(512u,true);
    card_stream[513u]^=0x01u; /* corrupt ONLY the wire CRC */
    CHECK(rcvr_datablock(sector,512u)==0);
    CHECK(s_sd_burst_cap==0 && mmc_sd_burst_error_count()>=1u);
    CHECK(burst_started==1u && portal_reads==1u);
    cursor=0u;bytes_polled=0u;waiting=false;
    CHECK(rcvr_datablock(sector,512u)==1); /* sticky legacy fallback */
    check_bytes(sector,512u);
    CHECK(burst_started==1u && bytes_polled==515u);
    prepare(512u,true);
    force_error=true;
    CHECK(rcvr_datablock(sector,512u)==0);
    CHECK(burst_started==1u && burst_aborted==1u && portal_reads==0u);
    CHECK(bytes_polled==1u && mmc_sd_burst_error_count()>=1u);

    prepare(512u,true);
    force_timeout=true;
    CHECK(rcvr_datablock(sector,512u)==0);
    CHECK(burst_started==1u && burst_aborted==1u && portal_reads==0u);
    CHECK(scheduler_yields>=100u && fake_us>=200000u);
    puts("PASS M3 real FatFS SD driver: 512B burst, M2 fallback, SD CRC16, errors and timeout");
    return 0;
}
