#include "mcu_mod_sample_store.h"
#include "fpga_spi.h"
#include <stdint.h>
#include <string.h>

/* J2R9B: 8-KiB SRAM per voice, four independently cached 2-KiB windows.
 * The LRU metadata adds only a few bytes per window, with all payload in
 * static BSS. No malloc, no FPGA register/SDRAM layout changes. */
typedef struct {
    uint32_t page, stamp;
    bool valid;
    uint8_t bytes[MOD_STORE_FETCH_BYTES];
} sample_window_t;
typedef struct {
    uintptr_t sample_token;
    uint32_t sample_length;
    bool sample_valid;
    sample_window_t window[MOD_STORE_WINDOWS];
} sample_cache_t;
static sample_cache_t s_cache[MOD_STORE_VOICES];
static uint32_t s_touch_clock;
static uint32_t s_sample_token[31];
static uint32_t s_sample_length[31];
static uint32_t s_size,s_misses,s_faults,s_read_bytes;

void mod_store_invalidate(void)
{
    s_touch_clock=0u;
    for(unsigned i=0;i<MOD_STORE_VOICES;i++) {
        s_cache[i].sample_valid=false;
        for(unsigned j=0;j<MOD_STORE_WINDOWS;j++)
            s_cache[i].window[j].valid=false;
    }
}
bool mod_store_begin(const uint32_t lengths[31])
{
    uint32_t cursor=0;
    mod_store_invalidate();
    s_faults=s_misses=s_read_bytes=0;
    s_size=0;
    if(!lengths)return false;
    for(unsigned i=0;i<31;i++){
        s_sample_token[i]=MOD_SDRAM_BASE+cursor;
        s_sample_length[i]=lengths[i];
        if(lengths[i]>MOD_SDRAM_CAPACITY-cursor)return false;
        cursor+=lengths[i];
    }
    s_size=cursor;
    return true;
}
uint32_t mod_store_size(void){return s_size;}
uint32_t mod_store_faults(void){return s_faults;}
uint32_t mod_store_misses(void){return s_misses;}
uint32_t mod_store_read_bytes(void){return s_read_bytes;}
bool mod_store_stage(uint32_t offset,const uint8_t *data,uint16_t len)
{
    if(!data || len==0 || offset>s_size || len>s_size-offset)
        return false;
    fpga_spi_xfer_write(FPGA_SPACE_SDRAM,MOD_SDRAM_BASE+offset,data,len);
    /* The audio task never stages and renders simultaneously. */
    return true;
}
bool mod_store_verify(uint32_t offset,const uint8_t *expected,uint16_t len)
{
    uint8_t got[32];
    if(!expected || len==0 || len>sizeof(got) || offset>s_size ||
       len>s_size-offset)return false;
    fpga_spi_xfer_read(FPGA_SPACE_SDRAM,MOD_SDRAM_BASE+offset,got,len);
    return memcmp(got,expected,len)==0;
}
static bool resolve(sample_cache_t *c,uintptr_t token,uint32_t index,
                    uint32_t *address)
{
    if(!c->sample_valid || c->sample_token!=token) {
        c->sample_valid=false;
        for(unsigned i=0;i<31;i++) {
            if(token==(uintptr_t)s_sample_token[i] && s_sample_length[i]) {
                c->sample_token=token;
                c->sample_length=s_sample_length[i];
                c->sample_valid=true;
                break;
            }
        }
    }
    if(!c->sample_valid || index>=c->sample_length) {
        /* A bad note/offset must never read into the following instrument. */
        if(!c->sample_valid)++s_faults;
        return false;
    }
    if(token<MOD_SDRAM_BASE || token-MOD_SDRAM_BASE>s_size ||
       index>s_size-(uint32_t)(token-MOD_SDRAM_BASE)) {
        ++s_faults;
        return false;
    }
    *address=(uint32_t)(token+index);
    return true;
}
mchar mod_store_read(void *unused,const mchar *virtual_base,
                     mulong byte_offset,unsigned voice)
{
    (void)unused;
    if(voice>=MOD_STORE_VOICES) {++s_faults;return 0;}
    sample_cache_t *c=&s_cache[voice];
    uint32_t addr;
    if(!resolve(c,(uintptr_t)virtual_base,(uint32_t)byte_offset,&addr))
        return 0;
    const uint32_t page=addr&~(MOD_STORE_FETCH_BYTES-1u);
    sample_window_t *hit=NULL;
    for(unsigned j=0;j<MOD_STORE_WINDOWS;j++) {
        if(c->window[j].valid && c->window[j].page==page) {
            hit=&c->window[j];
            break;
        }
    }
    if(!hit) {
        /* Prefer an unused window, otherwise evict the least recently
         * accessed window. All four metadata entries stay in MCU SRAM. */
        unsigned victim=0u;
        bool unused=false;
        for(unsigned j=0;j<MOD_STORE_WINDOWS;j++) {
            if(!c->window[j].valid) {
                victim=j;
                unused=true;
                break;
            }
        }
        if(!unused) {
            uint32_t oldest=0u;
            for(unsigned j=0;j<MOD_STORE_WINDOWS;j++) {
                const uint32_t age=s_touch_clock-c->window[j].stamp;
                if(j==0u || age>oldest) {
                    victim=j;
                    oldest=age;
                }
            }
        }
        const uint32_t pageoff=page-MOD_SDRAM_BASE;
        if(page<MOD_SDRAM_BASE || pageoff>=s_size){++s_faults;return 0;}
        const uint16_t len=(uint16_t)((s_size-pageoff)<MOD_STORE_FETCH_BYTES ?
                                      (s_size-pageoff) : MOD_STORE_FETCH_BYTES);
        hit=&c->window[victim];
        /* Unchanged, proven J2R9A bytewise SDRAM protocol, but fewer bytes
         * per *blocking* cache miss: 2KiB versus previous 8KiB. */
        fpga_spi_xfer_read(FPGA_SPACE_SDRAM,page,hit->bytes,len);
        if(len<MOD_STORE_FETCH_BYTES)
            memset(hit->bytes+len,0,MOD_STORE_FETCH_BYTES-len);
        hit->page=page;
        hit->valid=true;
        ++s_misses;
        s_read_bytes+=(uint32_t)len;
    }
    hit->stamp=++s_touch_clock;
    return (mchar)hit->bytes[addr-page];
}
void mod_store_write(void *unused,const mchar *virtual_base,
                     mulong byte_offset,mchar value)
{
    (void)unused;
    uintptr_t token=(uintptr_t)virtual_base;
    uint32_t addr;
    /* Invert-loop is rare; update every resident cache of this SDRAM byte. */
    if(!resolve(&s_cache[0],token,(uint32_t)byte_offset,&addr))return;
    uint8_t v=(uint8_t)value;
    fpga_spi_xfer_write(FPGA_SPACE_SDRAM,addr,&v,1u);
    const uint32_t page=addr&~(MOD_STORE_FETCH_BYTES-1u);
    for(unsigned i=0;i<MOD_STORE_VOICES;i++)
        for(unsigned j=0;j<MOD_STORE_WINDOWS;j++) {
            sample_window_t *w=&s_cache[i].window[j];
            if(w->valid && w->page==page)
                w->bytes[addr-page]=v;
        }
}
