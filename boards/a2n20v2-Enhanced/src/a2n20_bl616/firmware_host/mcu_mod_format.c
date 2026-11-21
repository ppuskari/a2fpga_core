/* J2R3: strict, bounded parser for the actual MOD signatures HxCMOD knows.
 * HxCMOD accepts multichannel signatures; no XM/S3M/IT support exists. */
#include "mcu_mod_format.h"
#include <string.h>

static uint16_t be16(const uint8_t *p)
{
    return (uint16_t)(((uint16_t)p[0]<<8)|p[1]);
}
/* Return 0 for unknown/unsupported signatures, 1..8 for supported MODs. */
static unsigned hxcmod_channels(const uint8_t *sig)
{
    static const char *const four[]={
        "M.K.","M!K!","M&K!","PATT","NSMS","LARD","FEST",
        "FIST","N.T.",NULL
    };
    for(unsigned i=0;four[i];i++)
        if(!memcmp(sig,four[i],4))return 4u;
    if(!memcmp(sig,"OKTA",4) || !memcmp(sig,"OCTA",4))
        return 8u;

    /* HxCMOD's modlist[] recognizes digit wildcards for these families:
     * $CHN, $$CH, $$CN, $$$C, FLT$, EXO$, CD$1, TDZ$, FA0$.
     * Only counts 1..8 are enabled here; larger formats stay rejected. */
    static const char *const masks[]={
        "$CHN","$$CH","$$CN","$$$C","FLT$","EXO$","CD$1",
        "TDZ$","FA0$",NULL
    };
    for(unsigned m=0;masks[m];m++) {
        unsigned channels=0u;
        bool match=true;
        for(unsigned i=0;i<4u;i++) {
            if(masks[m][i]=='$') {
                if(sig[i]<'0' || sig[i]>'9'){match=false;break;}
                channels=channels*10u+(unsigned)(sig[i]-'0');
            }else if(sig[i]!=(uint8_t)masks[m][i]) {
                match=false;break;
            }
        }
        if(match && channels>=1u && channels<=8u)return channels;
    }
    return 0u;
}
static bool parse_layout(const uint8_t *h,uint32_t size,
                         unsigned sample_count,unsigned header_bytes,
                         unsigned channels,mod_format_t *f)
{
    const unsigned songlen_offset=20u+30u*sample_count;
    const unsigned order_offset=songlen_offset+2u;
    const unsigned length=h[songlen_offset];
    uint32_t maxpat=0u,total=0u;
    if(channels<1u || channels>8u || !length || length>128u)return false;
    for(unsigned i=0;i<length;i++){
        if(h[order_offset+i]>127u)return false;
        if(h[order_offset+i]>maxpat)maxpat=h[order_offset+i];
    }
    f->header_bytes=header_bytes;
    f->song_length=(uint8_t)length;
    f->pattern_count=(uint8_t)(maxpat+1u);
    f->sample_count=(uint8_t)sample_count;
    f->channels=(uint8_t)channels;
    f->pattern_bytes=(maxpat+1u)*(256u*channels);
    f->prefix_bytes=header_bytes+f->pattern_bytes;
    if(f->prefix_bytes>size)return false;
    for(unsigned i=0;i<sample_count;i++){
        const unsigned off=20u+i*30u+22u;
        const uint32_t n=(uint32_t)be16(h+off)*2u;
        const uint32_t rep=(uint32_t)be16(h+off+4u)*2u;
        /* Empty instrument slots may contain tracker-specific loop sentinels.
         * HxCMOD ignores their metadata because zero-length samples are not
         * loaded. Keep strict bounds for instruments with real PCM data. */
        if(n && rep>n)return false;
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

    /* Important: absent a valid MOD signature, HxCMOD falls back to the
     * 15-instrument SoundTracker layout. Never interpret known incompatible
     * tracker formats as SoundTracker simply because extension is ".MOD". */
    if(!memcmp(header,"IMPM",4) ||
       !memcmp(header,"Extended Module:",16) ||
       !memcmp(header+44u,"SCRM",4))return false;

    const unsigned channels=hxcmod_channels(header+1080u);
    if(channels)
        return parse_layout(header,file_bytes,31u,1084u,channels,out);

    /* Genuine early SoundTracker MOD: 15 instruments, no magic at 1080,
     * fixed four-channel pattern events. Preserve J2 legacy acceptance.
     * Require plausible instrument volumes and finetune nibble. */
    for(unsigned i=0;i<15u;i++){
        const uint8_t *p=header+20u+i*30u;
        if(p[25]>64u || (p[24]&0xf0u)!=0u)return false;
    }
    return parse_layout(header,file_bytes,15u,600u,4u,out);
}
