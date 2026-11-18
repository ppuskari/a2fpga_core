/*
 * SenseiPlay8: runtime 31-instrument four-channel MOD parser.
 * No pregenerated files or offline song-specific firmware.
 *
 * Stage A: parse and build DOC wave image. Stage B will stream image
 * to the active DOC RAM via a dedicated FPGA handshake.
 */
#include "sensei_mod_decode.h"
#include <string.h>

static unsigned be16(const uint8_t *p)
{
    return ((unsigned)p[0] << 8) | p[1];
}

static unsigned ceil_wave(unsigned n)
{
    unsigned x=256u;
    while (x<n && x<8192u) x<<=1;
    return x;
}

static bool is_4ch(const uint8_t *s)
{
    return memcmp(s,"M.K.",4)==0 || memcmp(s,"M!K!",4)==0 ||
           memcmp(s,"4CHN",4)==0 || memcmp(s,"FLT4",4)==0;
}

bool sensei_mod_decode(const uint8_t *file, size_t length,
                       uint8_t *pcm, size_t pcm_cap,
                       sensei_mod_decoded_t *out)
{
    unsigned npat=0;
    size_t sample_offset, bank_size=0;
    if (!file || !pcm || !out || length<1084 || !is_4ch(file+1080))
        return false;
    memset(out,0,sizeof(*out));
    if (file[950]==0 || file[950]>128) return false;
    out->order_count=file[950];
    for(unsigned o=0;o<out->order_count;o++) {
        unsigned pat=file[952+o];
        if (pat>=128u)return false;
        out->orders[o]=(uint8_t)pat;
        if (pat+1u>npat)npat=pat+1u;
    }
    if (npat==0 || 1024u*npat>length-1084u)return false;
    out->pattern_count=(uint16_t)npat;
    out->pattern_offset=1084u;
    sample_offset=1084u+1024u*npat;
    for(unsigned inst=1;inst<=31;inst++) {
        const size_t head=20u+30u*(inst-1u);
        const unsigned full=be16(file+head+22u)*2u;
        const unsigned volume=file[head+25u];
        unsigned loop_start=be16(file+head+26u)*2u;
        unsigned loop_len=be16(file+head+28u)*2u;
        bool looping=loop_len>=64u && loop_start+loop_len<=full;
        unsigned wanted=looping?loop_len:full;
        unsigned size;
        const uint8_t *src;
        size_t aligned;
        unsigned wts, tocopy;
        if (volume>64 || full>length-sample_offset)return false;
        src=file+sample_offset+(looping?loop_start:0);
        sample_offset+=full;
        out->file_sample_bytes+=(uint32_t)full;
        if(full==0)continue;
        if(wanted>8192u)return false;
        size=ceil_wave(wanted);
        if(size<wanted)return false;
        aligned=(bank_size+(size-1u)) & ~((size_t)size-1u);
        if (aligned+size>pcm_cap || aligned+size>49152u)return false;
        memset(pcm+bank_size,0x80,aligned-bank_size);
        memset(pcm+aligned,0x80,size);
        tocopy=wanted;
        if (!looping && tocopy==size)tocopy--; /* reserve DOC HALT byte */
        for(unsigned i=0;i<tocopy;i++) {
            uint8_t value=(uint8_t)(src[i]^0x80u);
            pcm[aligned+i]=value?value:1u;
        }
        if (!looping)pcm[aligned+size-1u]=0u;
        wts=0;
        for(unsigned x=size;x>256u;x>>=1)wts++;
        out->catalog[inst*4u]=(uint8_t)(aligned/256u);
        out->catalog[inst*4u+1u]=(uint8_t)((wts<<3)|wts);
        out->catalog[inst*4u+2u]=(uint8_t)(looping?0u:2u);
        out->catalog[inst*4u+3u]=(uint8_t)volume;
        bank_size=aligned+size;
    }
    out->doc_pcm_bytes=(uint32_t)bank_size;
    return bank_size!=0;
}
