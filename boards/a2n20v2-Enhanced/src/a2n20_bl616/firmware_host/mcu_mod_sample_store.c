#include "mcu_mod_sample_store.h"
#include "fpga_spi.h"
#include <stdint.h>
#include <string.h>

/* Kept in static BSS: no malloc from the real-time audio render path. */
typedef struct {
    uint32_t page;
    uintptr_t sample_token;
    uint32_t sample_length;
    bool page_valid, sample_valid;
    uint8_t bytes[MOD_STORE_PAGE];
} sample_cache_t;
static sample_cache_t s_cache[MOD_STORE_VOICES];
static uint32_t s_sample_token[31];
static uint32_t s_sample_length[31];
static uint32_t s_size,s_misses,s_faults,s_read_bytes;

void mod_store_invalidate(void)
{
    for(unsigned i=0;i<MOD_STORE_VOICES;i++) {
        s_cache[i].page_valid=false;
        s_cache[i].sample_valid=false;
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
    uint32_t page=addr&~(MOD_STORE_PAGE-1u);
    if(!c->page_valid || c->page!=page) {
        uint32_t pageoff=page-MOD_SDRAM_BASE;
        if(page<MOD_SDRAM_BASE || pageoff>=s_size){++s_faults;return 0;}
        uint16_t len=(uint16_t)((s_size-pageoff)<MOD_STORE_PAGE ?
                                (s_size-pageoff) : MOD_STORE_PAGE);
        /* SPI read happens at a 4-KiB cache boundary, not every PCM frame. */
        fpga_spi_xfer_read(FPGA_SPACE_SDRAM,page,c->bytes,len);
        if(len<MOD_STORE_PAGE)memset(c->bytes+len,0,MOD_STORE_PAGE-len);
        c->page=page;
        c->page_valid=true;
        ++s_misses;
        s_read_bytes+=(uint32_t)len;
    }
    return (mchar)c->bytes[addr-page];
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
    uint32_t page=addr&~(MOD_STORE_PAGE-1u);
    for(unsigned i=0;i<MOD_STORE_VOICES;i++)
        if(s_cache[i].page_valid && s_cache[i].page==page)
            s_cache[i].bytes[addr-page]=v;
}
