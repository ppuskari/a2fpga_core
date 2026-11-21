#include "mcu_mod_format.h"
#include <string.h>

static uint16_t be16(const uint8_t *p)
{
    return (uint16_t)(((uint16_t)p[0]<<8)|p[1]);
}
static bool is_4chan(const uint8_t *sig)
{
    static const char *const fixed[]={
        "M.K.","M!K!","M&K!","PATT","NSMS","LARD","FEST",
        "FIST","N.T.",NULL
    };
    for(unsigned i=0;fixed[i];i++)
        if(!memcmp(sig,fixed[i],4))return true;
    if((sig[0]=='4' && sig[1]=='C' && sig[2]=='H' && sig[3]=='N') ||
       (sig[0]=='F' && sig[1]=='L' && sig[2]=='T' && sig[3]=='4') ||
       (sig[0]=='E' && sig[1]=='X' && sig[2]=='O' && sig[3]=='4') ||
       (sig[0]=='C' && sig[1]=='D' && sig[2]=='4' && sig[3]=='1') ||
       (sig[0]=='T' && sig[1]=='D' && sig[2]=='Z' && sig[3]=='4') ||
       (sig[0]=='F' && sig[1]=='A' && sig[2]=='0' && sig[3]=='4'))
        return true;
    return false;
}
static bool parse_layout(const uint8_t *h,uint32_t size,
                         unsigned sample_count,unsigned header_bytes,
                         mod_format_t *f)
{
    unsigned songlen_offset=20u+30u*sample_count;
    unsigned order_offset=songlen_offset+2u;
    unsigned length=h[songlen_offset];
    uint32_t maxpat=0,total=0;
    if(!length || length>128)return false;
    for(unsigned i=0;i<length;i++){
        if(h[order_offset+i]>127)return false;
        if(h[order_offset+i]>maxpat)maxpat=h[order_offset+i];
    }
    f->header_bytes=header_bytes;
    f->song_length=(uint8_t)length;
    f->pattern_count=(uint8_t)(maxpat+1u);
    f->sample_count=(uint8_t)sample_count;
    f->pattern_bytes=(maxpat+1u)*1024u;
    f->prefix_bytes=header_bytes+f->pattern_bytes;
    if(f->prefix_bytes>size)return false;
    for(unsigned i=0;i<sample_count;i++){
        unsigned off=20u+i*30u+22u;
        uint32_t n=(uint32_t)be16(h+off)*2u;
        uint32_t rep=(uint32_t)be16(h+off+4u)*2u;
        if(rep>n)return false;
        f->lengths[i]=n;
        if(n>0x200000u-total)return false;
        total+=n;
    }
    f->sample_bytes=total;
    return total<=size-f->prefix_bytes;
}
bool mod_format_probe(const uint8_t header[MOD_HEADER_PROBE],
                      uint32_t file_bytes,mod_format_t *out)
{
    if(!header || !out || file_bytes<MOD_HEADER_PROBE ||
       file_bytes>MOD_TOTAL_FILE_MAX)return false;
    memset(out,0,sizeof(*out));
    if(is_4chan(header+1080u))
        return parse_layout(header,file_bytes,31u,1084u,out);
    /* HxCMOD falls back to genuine SoundTracker 15-instrument files. A
     * plausible 15-instrument header is required; random unknown 31-sample
     * signatures do not become valid automatically. */
    for(unsigned i=0;i<15u;i++){
        const uint8_t *p=header+20u+i*30u;
        if(p[25]>64u || (p[24]&0xf0u)!=0u)return false;
    }
    return parse_layout(header,file_bytes,15u,600u,out);
}
