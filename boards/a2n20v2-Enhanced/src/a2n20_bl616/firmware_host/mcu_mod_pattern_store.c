/* J2R8: 16-KiB variable-size LRU HxCMOD pattern cache in MCU SRAM.
 * The 16-KiB area contains sixteen 1-KiB pages, supporting:
 *  - sixteen 4-channel patterns (1024B each)
 *  - eight 6/8-channel patterns (1536/2048B each)
 * Every pattern is still stored in FPGA SDRAM at byte 0x600000.
 * HxCMOD consumes each returned pointer synchronously for one row.
 * No dynamic allocation or copying is required on a cache hit.
 */
#include "mcu_mod_pattern_store.h"
#include "fpga_spi.h"
#include <string.h>

_Static_assert(sizeof(note)==4u, "MOD pattern events must be four bytes");
_Static_assert(MOD_PATTERN_CACHE_BYTES==16u*MOD_PATTERN_CACHE_PAGE_BYTES,
               "cache page partition must cover exactly 16 KiB");

typedef struct {
    unsigned pattern;
    unsigned start_page;
    unsigned pages;
    uint32_t last_use;
    bool valid;
} pattern_slot_t;

/* 16384B exactly, plus small separately accounted slot metadata. */
static note s_cache[MOD_PATTERN_CACHE_BYTES/sizeof(note)];
static pattern_slot_t s_slot[MOD_PATTERN_CACHE_PAGES];
static uint32_t s_clock;
static uint32_t s_total,s_fills,s_hits,s_reads,s_faults,s_evictions;
static unsigned s_channels,s_count;

void mod_patterns_invalidate(void)
{
    memset(s_slot,0,sizeof s_slot);
    s_clock=0u;
}
bool mod_patterns_begin(unsigned channels,unsigned pattern_count)
{
    mod_patterns_invalidate();
    s_total=s_fills=s_hits=s_reads=s_faults=s_evictions=0u;
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
uint32_t mod_patterns_evictions(void) { return s_evictions; }
bool mod_patterns_stage(uint32_t offset,const uint8_t *data,uint16_t length)
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
static bool overlaps(const pattern_slot_t *slot,unsigned start,unsigned pages)
{
    return slot->valid && slot->start_page < start+pages &&
           start < slot->start_page+slot->pages;
}
note *mod_patterns_get(void *opaque,unsigned pattern,unsigned channels)
{
    (void)opaque;
    if(!s_total || pattern>=s_count || channels!=s_channels) {
        ++s_faults;
        mod_patterns_invalidate();
        memset(s_cache,0,MOD_PATTERN_CACHE_BYTES);
        return s_cache;
    }
    for(unsigned i=0;i<MOD_PATTERN_CACHE_PAGES;i++) {
        if(s_slot[i].valid && s_slot[i].pattern==pattern) {
            ++s_hits;
            s_slot[i].last_use=++s_clock;
            return s_cache+s_slot[i].start_page*
                            (MOD_PATTERN_CACHE_PAGE_BYTES/sizeof(note));
        }
    }
    const uint32_t length=256u*channels;
    const uint32_t offset=(uint32_t)pattern*length;
    if(offset>s_total || length>s_total-offset) {
        ++s_faults;
        mod_patterns_invalidate();
        memset(s_cache,0,MOD_PATTERN_CACHE_BYTES);
        return s_cache;
    }
    const unsigned pages=(length+MOD_PATTERN_CACHE_PAGE_BYTES-1u)/
                          MOD_PATTERN_CACHE_PAGE_BYTES;
    /* All patterns are <=2 KiB and use at most two contiguous pages.
     * Prefer the lowest eviction count, then the oldest resident entries.
     * Metadata search is bounded to <=16*16 comparisons per miss. */
    unsigned best_start=0u,best_conflicts=MOD_PATTERN_CACHE_PAGES+1u;
    uint64_t best_age=0u;
    for(unsigned start=0;start+pages<=MOD_PATTERN_CACHE_PAGES;start++) {
        unsigned conflicts=0u;
        uint64_t age=0u;
        for(unsigned i=0;i<MOD_PATTERN_CACHE_PAGES;i++) {
            if(overlaps(&s_slot[i],start,pages)) {
                ++conflicts;
                age+=(uint32_t)(s_clock-s_slot[i].last_use);
            }
        }
        if(conflicts<best_conflicts ||
           (conflicts==best_conflicts && age>best_age)) {
            best_start=start;
            best_conflicts=conflicts;
            best_age=age;
        }
    }
    for(unsigned i=0;i<MOD_PATTERN_CACHE_PAGES;i++) {
        if(overlaps(&s_slot[i],best_start,pages)) {
            s_slot[i].valid=false;
            ++s_evictions;
        }
    }
    unsigned meta=MOD_PATTERN_CACHE_PAGES;
    for(unsigned i=0;i<MOD_PATTERN_CACHE_PAGES;i++) {
        if(!s_slot[i].valid) { meta=i; break; }
    }
    /* If all sixteen metadata slots were occupied then at least one
     * resident pattern was evicted immediately above. */
    if(meta==MOD_PATTERN_CACHE_PAGES) {
        ++s_faults;
        mod_patterns_invalidate();
        memset(s_cache,0,MOD_PATTERN_CACHE_BYTES);
        return s_cache;
    }
    note *dst=s_cache+best_start*
                     (MOD_PATTERN_CACHE_PAGE_BYTES/sizeof(note));
    fpga_spi_xfer_read(FPGA_SPACE_SDRAM,MOD_PATTERN_SDRAM_BASE+offset,
                       (uint8_t *)dst,(uint16_t)length);
    s_slot[meta].pattern=pattern;
    s_slot[meta].start_page=best_start;
    s_slot[meta].pages=pages;
    s_slot[meta].last_use=++s_clock;
    s_slot[meta].valid=true;
    ++s_fills;
    s_reads+=length;
    return dst;
}
