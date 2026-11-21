/* J2R7: four-slot / 8-KiB HxCMOD pattern cache in MCU SRAM.
 * Patterns remain in FPGA SDRAM at 0x600000. The SPI fetch occurs only on
 * a miss. An LRU replacement policy preserves recently repeated patterns.
 * HxCMOD consumes the returned pointer synchronously for one row.
 * No dynamic heap allocation. This file owns all cache writes.
 */
#include "mcu_mod_pattern_store.h"
#include "fpga_spi.h"
#include <string.h>

_Static_assert(sizeof(note) == 4u, "MOD note events must be four bytes");

static note s_cache[MOD_PATTERN_CACHE_SLOTS][64u * 8u];
static uint32_t s_recent[MOD_PATTERN_CACHE_SLOTS];
static unsigned s_index[MOD_PATTERN_CACHE_SLOTS];
static bool s_valid[MOD_PATTERN_CACHE_SLOTS];
static uint32_t s_clock;
static uint32_t s_total, s_fills, s_hits, s_reads, s_faults;
static unsigned s_channels, s_count;

void mod_patterns_invalidate(void)
{
    for(unsigned i=0;i<MOD_PATTERN_CACHE_SLOTS;i++) {
        s_recent[i]=0u;
        s_index[i]=0u;
        s_valid[i]=false;
    }
    s_clock=0u;
}
bool mod_patterns_begin(unsigned channels, unsigned pattern_count)
{
    mod_patterns_invalidate();
    s_total=s_fills=s_hits=s_reads=s_faults=0u;
    s_channels=s_count=0u;
    if(channels<1u || channels>8u ||
       pattern_count<1u || pattern_count>128u)
        return false;
    const uint32_t total=(uint32_t)pattern_count*256u*channels;
    if(total>MOD_PATTERN_SDRAM_CAPACITY)
        return false;
    s_total=total;
    s_channels=channels;
    s_count=pattern_count;
    return true;
}
uint32_t mod_patterns_bytes(void) { return s_total; }
uint32_t mod_patterns_fetch_count(void) { return s_fills; }
uint32_t mod_patterns_cache_hits(void) { return s_hits; }
uint32_t mod_patterns_read_bytes(void) { return s_reads; }
uint32_t mod_patterns_faults(void) { return s_faults; }
bool mod_patterns_stage(uint32_t offset, const uint8_t *data, uint16_t length)
{
    if(!data || !length || offset>s_total || length>s_total-offset)
        return false;
    fpga_spi_xfer_write(FPGA_SPACE_SDRAM,
                        MOD_PATTERN_SDRAM_BASE+offset,data,length);
    return true;
}
bool mod_patterns_verify(uint32_t offset,const uint8_t *expected,
                         uint16_t length)
{
    uint8_t got[32];
    if(!expected || !length || length>sizeof got ||
       offset>s_total || length>s_total-offset)
        return false;
    fpga_spi_xfer_read(FPGA_SPACE_SDRAM,
                       MOD_PATTERN_SDRAM_BASE+offset,got,length);
    return memcmp(got,expected,length)==0;
}
note *mod_patterns_get(void *opaque, unsigned pattern, unsigned channels)
{
    (void)opaque;
    if(!s_total || pattern>=s_count || channels!=s_channels) {
        ++s_faults;
        memset(s_cache[0],0,sizeof s_cache[0]);
        s_valid[0]=false;
        return s_cache[0];
    }
    for(unsigned i=0;i<MOD_PATTERN_CACHE_SLOTS;i++) {
        if(s_valid[i] && s_index[i]==pattern) {
            ++s_hits;
            s_recent[i]=++s_clock;
            return s_cache[i];
        }
    }

    const uint32_t length=256u*channels;
    const uint32_t offset=(uint32_t)pattern*length;
    if(offset>s_total || length>s_total-offset) {
        ++s_faults;
        memset(s_cache[0],0,sizeof s_cache[0]);
        s_valid[0]=false;
        return s_cache[0];
    }

    /* Choose an unused slot, else the least-recently used resident slot.
     * Unsigned age subtraction handles 32-bit clock rollover. */
    unsigned slot=0u;
    bool have_free=false;
    for(unsigned i=0;i<MOD_PATTERN_CACHE_SLOTS;i++) {
        if(!s_valid[i]) {
            slot=i;
            have_free=true;
            break;
        }
    }
    if(!have_free) {
        uint32_t oldest=0u;
        for(unsigned i=0;i<MOD_PATTERN_CACHE_SLOTS;i++) {
            const uint32_t age=s_clock-s_recent[i];
            if(i==0u || age>oldest) {
                slot=i;
                oldest=age;
            }
        }
    }
    fpga_spi_xfer_read(FPGA_SPACE_SDRAM,
                       MOD_PATTERN_SDRAM_BASE+offset,
                       (uint8_t *)s_cache[slot],(uint16_t)length);
    s_index[slot]=pattern;
    s_recent[slot]=++s_clock;
    s_valid[slot]=true;
    ++s_fills;
    s_reads+=length;
    return s_cache[slot];
}
