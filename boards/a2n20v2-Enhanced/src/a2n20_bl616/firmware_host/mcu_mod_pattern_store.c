/* J2R6: cache one entire HxCMOD pattern in SRAM, with all remaining patterns
 * stored in the FPGA at 0x600000. SPI transfers happen only on pattern
 * transitions (~64 rows), never once per PCM sample. No heap allocation.
 */
#include "mcu_mod_pattern_store.h"
#include "fpga_spi.h"
#include <string.h>

static note s_cache[64u * 8u]; /* 2048B: maximum 8-channel pattern */
static uint32_t s_total, s_fills, s_hits, s_reads, s_faults;
static unsigned s_channels, s_count, s_cached;
static bool s_valid;

void mod_patterns_invalidate(void)
{
    s_valid = false;
    s_cached = 0u;
}
bool mod_patterns_begin(unsigned channels, unsigned pattern_count)
{
    mod_patterns_invalidate();
    s_total = s_fills = s_hits = s_reads = s_faults = 0u;
    s_channels = s_count = 0u;
    if(channels < 1u || channels > 8u ||
       pattern_count < 1u || pattern_count > 128u)
        return false;
    uint32_t total = (uint32_t)pattern_count * 256u * channels;
    if(total > MOD_PATTERN_SDRAM_CAPACITY)
        return false;
    s_total = total;
    s_channels = channels;
    s_count = pattern_count;
    return true;
}
uint32_t mod_patterns_bytes(void) { return s_total; }
uint32_t mod_patterns_fetch_count(void) { return s_fills; }
uint32_t mod_patterns_cache_hits(void) { return s_hits; }
uint32_t mod_patterns_read_bytes(void) { return s_reads; }
uint32_t mod_patterns_faults(void) { return s_faults; }
bool mod_patterns_stage(uint32_t offset, const uint8_t *data, uint16_t length)
{
    if(!data || !length || offset > s_total || length > s_total-offset)
        return false;
    fpga_spi_xfer_write(FPGA_SPACE_SDRAM,
                        MOD_PATTERN_SDRAM_BASE+offset,data,length);
    return true;
}
bool mod_patterns_verify(uint32_t offset, const uint8_t *expected,
                         uint16_t length)
{
    uint8_t got[32];
    if(!expected || !length || length > sizeof got ||
       offset > s_total || length > s_total-offset)
        return false;
    fpga_spi_xfer_read(FPGA_SPACE_SDRAM,
                       MOD_PATTERN_SDRAM_BASE+offset,got,length);
    return memcmp(got,expected,length)==0;
}
note *mod_patterns_get(void *opaque, unsigned pattern, unsigned channels)
{
    (void)opaque;
    if(!s_total || pattern >= s_count || channels != s_channels) {
        ++s_faults;
        memset(s_cache,0,sizeof s_cache);
        s_valid=false;
        return s_cache; /* Never give HxCMOD a NULL pattern pointer. */
    }
    if(s_valid && pattern==s_cached) {
        ++s_hits;
        return s_cache;
    }
    const uint32_t length = 256u * channels;
    const uint32_t offset = (uint32_t)pattern * length;
    if(offset > s_total || length > s_total-offset) {
        ++s_faults;
        memset(s_cache,0,sizeof s_cache);
        s_valid=false;
        return s_cache;
    }
    fpga_spi_xfer_read(FPGA_SPACE_SDRAM,MOD_PATTERN_SDRAM_BASE+offset,
                       (uint8_t *)s_cache,(uint16_t)length);
    s_cached=pattern;
    s_valid=true;
    ++s_fills;
    s_reads+=length;
    return s_cache;
}
