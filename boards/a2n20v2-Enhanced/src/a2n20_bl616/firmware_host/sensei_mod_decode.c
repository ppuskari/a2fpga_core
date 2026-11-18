/*
 * SenseiPlay8 P2R: runtime four-channel ProTracker 31-instrument decoder.
 *
 * Preserve the attack and exact loop start: an attack waveform uses DOC
 * MODE_SWAP (3) and a separate paired oscillator loops the sustain using
 * MODE_FREE (0). The DOC itself switches oscillators upon the attack's
 * zero-byte sentinel; no FreeRTOS timer or IIe overhead is involved.
 *
 * The DOC waveform length must be a power of two and >=256 bytes. For
 * small loops we repeat source data to fill the DOC page. Non-power-of-two
 * loops still have a final wrap discontinuity: a later software PCM
 * backend will be required for sample-exact arbitrary loop lengths.
 *
 * Per-instrument catalog (32 * 8 bytes):
 * 0 attack WTP; 1 attack RTS; 2 attack CTRL mode bits (bits 2:1)
 * 3 volume (0..64)
 * 4 sustain WTP; 5 sustain RTS; 6 sustain CTRL; 7 flags
 * flags bit 0 = two-phase attack->sustain with DOC SWAP.
 * For loop-start=0, use a single free-running waveform.
 * For no-loop, use a single one-shot waveform.
 */
#include "sensei_mod_decode.h"
#include <string.h>

#define P2_MAX_BANK_BYTES 49152u
#define DOC_MIN_WAVE 256u
#define DOC_MAX_WAVE 8192u
#define DOC_MODE_FREE     0u
#define DOC_MODE_ONE_SHOT 2u   /* mode 01 in control bits 2:1 */
#define DOC_MODE_SWAP     6u   /* mode 11 in control bits 2:1 */

static unsigned be16(const uint8_t *p) {
    return ((unsigned)p[0] << 8) | p[1];
}
static unsigned ceil_wave(unsigned n) {
    unsigned x=DOC_MIN_WAVE;
    while(x<n && x<DOC_MAX_WAVE)x<<=1;
    return x;
}
static bool is_4ch(const uint8_t *s) {
    return memcmp(s,"M.K.",4)==0 || memcmp(s,"M!K!",4)==0 ||
           memcmp(s,"4CHN",4)==0 || memcmp(s,"FLT4",4)==0;
}

/* Each DOC waveform is naturally aligned to its own power-of-two length
 * because the DOC masks WTP according to table size. */
static bool append_wave(uint8_t *pcm,size_t cap,size_t *bank,
                        const uint8_t *src,unsigned length,
                        bool repeating,bool halt_on_end,
                        uint8_t *wtp,uint8_t *rts)
{
    unsigned size;
    size_t aligned;
    if(!length || length>DOC_MAX_WAVE)return false;
    /* Include a sentinel byte if sample length is exactly power-of-two
     * and an exact end sentinel is explicitly required; if the table
     * ends at its hardware limit, one-shot overflow ends the note. */
    unsigned required=length;
    if(halt_on_end && length<DOC_MAX_WAVE &&
       ceil_wave(length)==length)
        required=length+1u;
    size=ceil_wave(required);
    if(size<required)return false;
    aligned=(*bank+size-1u)&~((size_t)size-1u);
    if(aligned+size>P2_MAX_BANK_BYTES || (pcm && aligned+size>cap))
        return false;
    if(pcm) {
        memset(pcm+*bank,0x80,aligned-*bank);
        memset(pcm+aligned,0x80,size);
        for(unsigned i=0;i<(repeating?size:length);i++){
            const unsigned index=repeating?i%length:i;
            uint8_t encoded=(uint8_t)(src[index]^0x80u);
            /* $00 is the DOC terminator, not a valid PCM value. */
            pcm[aligned+i]=encoded?encoded:1u;
        }
        if(halt_on_end && length<size)
            pcm[aligned+length]=0u; /* transition exactly at loop start */
    }
    unsigned wts=0;
    for(unsigned x=size;x>DOC_MIN_WAVE;x>>=1)wts++;
    *wtp=(uint8_t)(aligned/256u);
    *rts=(uint8_t)((wts<<3)|wts);
    *bank=aligned+size;
    return true;
}

bool sensei_mod_decode(const uint8_t *file,size_t length,
                       uint8_t *pcm,size_t pcm_cap,
                       sensei_mod_decoded_t *out)
{
    unsigned npat=0;
    size_t sample_offset,bank_size=0;
    if(!file || !out || length<1084u || !is_4ch(file+1080u) ||
       (!pcm && pcm_cap!=0))return false;
    memset(out,0,sizeof(*out));
    if(!file[950] || file[950]>128u)return false;
    out->order_count=file[950];
    for(unsigned o=0;o<out->order_count;o++) {
        unsigned pat=file[952u+o];
        if(pat>=128u)return false;
        out->orders[o]=(uint8_t)pat;
        if(pat+1u>npat)npat=pat+1u;
    }
    if(!npat || 1024u*npat>length-1084u)return false;
    out->pattern_count=(uint16_t)npat;
    out->pattern_offset=1084u;
    sample_offset=1084u+1024u*npat;
    for(unsigned inst=1;inst<=31u;inst++) {
        const size_t head=20u+30u*(inst-1u);
        const unsigned full=be16(file+head+22u)*2u;
        const unsigned volume=file[head+25u];
        const unsigned loop_start=be16(file+head+26u)*2u;
        const unsigned loop_len=be16(file+head+28u)*2u;
        const bool looping=(loop_len>2u &&
            loop_start<full && loop_len<=full-loop_start);
        const uint8_t *src=file+sample_offset;
        uint8_t *d=out->catalog+inst*8u;
        if(volume>64u || full>length-sample_offset)return false;
        sample_offset+=full;
        out->file_sample_bytes+=(uint32_t)full;
        if(!full)continue;
        if(looping && loop_start) {
            /* First 0..loop_start-1 exactly once, then automatic DOC
             * SWAP to the free-running sustain oscillator. */
            if(!append_wave(pcm,pcm_cap,&bank_size,src,loop_start,
                            false,true,&d[0],&d[1]))return false;
            d[2]=DOC_MODE_SWAP;
            if(!append_wave(pcm,pcm_cap,&bank_size,src+loop_start,loop_len,
                            true,false,&d[4],&d[5]))return false;
            d[6]=DOC_MODE_FREE;d[7]=1u;
        } else if(looping) {
            if(!append_wave(pcm,pcm_cap,&bank_size,src+loop_start,loop_len,
                            true,false,&d[0],&d[1]))return false;
            d[2]=DOC_MODE_FREE;
        } else {
            if(!append_wave(pcm,pcm_cap,&bank_size,src,full,false,true,
                            &d[0],&d[1]))return false;
            d[2]=DOC_MODE_ONE_SHOT;
        }
        d[3]=(uint8_t)volume;
    }
    out->doc_pcm_bytes=(uint32_t)bank_size;
    return bank_size!=0;
}
