/* J2R9B: 8KiB retained SRAM per voice but smaller blocking SDRAM reads.
 * Host fake-FPGA test verifies actual subpage lengths, 8 independent voice
 * caches, LRU hits/misses and coherency of in-place sample inversion.
 * Also runs with 4KiB / 8KiB window sizes as A/B controls.
 */
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "fpga_spi.h"
#include "mcu_mod_sample_store.h"

#define CHECK(expr) do { if(!(expr)) { \
    fprintf(stderr,"FAIL sample windows line %d: %s\n",__LINE__,#expr); \
    exit(1); \
} } while (0)

#define SAMPLE_BYTES 65536u
static uint8_t fake_sdram[SAMPLE_BYTES];
static uint32_t spi_reads,spi_read_bytes,spi_max_read;

void fpga_spi_xfer_write(uint8_t space,uint32_t addr,const uint8_t *p,uint16_t n)
{
    CHECK(space==FPGA_SPACE_SDRAM);
    CHECK(addr>=MOD_SDRAM_BASE && addr-MOD_SDRAM_BASE<=SAMPLE_BYTES);
    CHECK(n<=SAMPLE_BYTES-(addr-MOD_SDRAM_BASE));
    memcpy(fake_sdram+(addr-MOD_SDRAM_BASE),p,n);
}
void fpga_spi_xfer_read(uint8_t space,uint32_t addr,uint8_t *p,uint16_t n)
{
    CHECK(space==FPGA_SPACE_SDRAM);
    CHECK(addr>=MOD_SDRAM_BASE && addr-MOD_SDRAM_BASE<=SAMPLE_BYTES);
    CHECK(n<=SAMPLE_BYTES-(addr-MOD_SDRAM_BASE));
    CHECK(n<=MOD_STORE_FETCH_BYTES);
    memcpy(p,fake_sdram+(addr-MOD_SDRAM_BASE),n);
    ++spi_reads;spi_read_bytes+=n;
    if(n>spi_max_read)spi_max_read=n;
}
static uint8_t value_at(uint32_t at)
{
    return (uint8_t)((at*37u+(at>>8)+17u)&0xFFu);
}
static uint8_t read_at(uint32_t addr,unsigned voice)
{
    return (uint8_t)mod_store_read(NULL,(const mchar *)(uintptr_t)MOD_SDRAM_BASE,
                                    addr,voice);
}
int main(void)
{
    uint32_t lengths[31]={0};
    lengths[0]=SAMPLE_BYTES;
    CHECK(MOD_STORE_PAGE==8192u);
    CHECK(MOD_STORE_WINDOWS*MOD_STORE_FETCH_BYTES==8192u);
    CHECK(mod_store_begin(lengths));
    static uint8_t data[4096];
    for(uint32_t at=0;at<SAMPLE_BYTES;at+=sizeof data) {
        for(uint32_t k=0;k<sizeof data;k++)data[k]=value_at(at+k);
        CHECK(mod_store_stage(at,data,sizeof data));
    }
    /* Every voice has independent capacity and cannot overwrite another
     * voice's window list, even when all voices stream different samples. */
    const unsigned resident=MOD_STORE_WINDOWS;
    for(unsigned voice=0;voice<MOD_STORE_VOICES;voice++) {
        for(unsigned j=0;j<resident;j++) {
            const uint32_t at=(uint32_t)j*MOD_STORE_FETCH_BYTES+voice*7u;
            CHECK(read_at(at,voice)==value_at(at));
        }
    }
    CHECK(spi_reads==8u*resident);
    CHECK(mod_store_misses()==8u*resident);
    CHECK(spi_max_read==MOD_STORE_FETCH_BYTES);
    CHECK(mod_store_read_bytes()==spi_read_bytes);
    /* Access every resident page in reverse order => all cache hits. */
    for(unsigned voice=0;voice<MOD_STORE_VOICES;voice++) {
        for(unsigned j=resident;j>0;j--) {
            const uint32_t at=(uint32_t)(j-1u)*MOD_STORE_FETCH_BYTES+voice*7u;
            CHECK(read_at(at,voice)==value_at(at));
        }
    }
    CHECK(spi_reads==8u*resident);
    /* All 8K of existing cache data still resident. Evict LRU window from
     * voice zero only. Page 0 is most recent, final page is oldest. */
    const uint32_t new_at=(uint32_t)resident*MOD_STORE_FETCH_BYTES+19u;
    CHECK(read_at(new_at,0u)==value_at(new_at));
    CHECK(spi_reads==8u*resident+1u);
    const uint32_t cached_at=13u;
    CHECK(read_at(cached_at,0u)==value_at(cached_at));
    CHECK(spi_reads==8u*resident+1u);
    const uint32_t evicted_at=(uint32_t)(resident-1u)*MOD_STORE_FETCH_BYTES+23u;
    CHECK(read_at(evicted_at,0u)==value_at(evicted_at));
    CHECK(spi_reads==8u*resident+2u);
    /* Invert-loop writes must update all resident copies of an SDRAM byte
     * across multiple voices without needing another read/cache miss. */
    CHECK(read_at(31u,1u)==value_at(31u));
    const uint32_t prev=spi_reads;
    mod_store_write(NULL,(const mchar *)(uintptr_t)MOD_SDRAM_BASE,31u,(mchar)0xA7);
    CHECK(fake_sdram[31u]==0xA7);
    CHECK(read_at(31u,1u)==0xA7);
    CHECK(read_at(31u,0u)==0xA7);
    CHECK(spi_reads==prev);
    CHECK(mod_store_faults()==0u);
    CHECK(mod_store_read_bytes()==spi_read_bytes);
    printf("PASS J2R9B: 8 voices x %u windows of %uB in %uB SRAM/voice; "
           "%u FPGA page reads, %u total bytes, no faults\n",
           resident,(unsigned)MOD_STORE_FETCH_BYTES,(unsigned)MOD_STORE_PAGE,
           (unsigned)spi_reads,(unsigned)spi_read_bytes);
    return 0;
}
