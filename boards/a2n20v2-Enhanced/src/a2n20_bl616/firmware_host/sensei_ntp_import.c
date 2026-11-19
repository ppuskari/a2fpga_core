/*
 * NinjaTrackerPlus v0/v2 DOC-ready reader, independently implemented
 * from the documented
 * format, the original Ninjaforce PHP converter and 65816 reference player.
 *
 * Source: https://github.com/antoinevignau/source/tree/master/ntpsources
 * Upstream author Jesse Blue / Ninjaforce. Source is not vendored.
 *
 * Important: this is the DOC-ready NTP SAMPLE/PATTERN IMPORT stage. P2U still
 * executes ProTracker tick effects, not the original 65816 NTP replay engine.
 */
#include "sensei_ntp_import.h"
#include <string.h>

/* A classic 31-instrument MOD can become at most 63 NTP instrument
 * records (31 heads + 31 loops + optional silent timer). Keep scratch
 * under 1 KB; the BL616 sensei worker has a 3072-byte stack. */
enum { NTP_HEADER=9, NTP_TRACKS=4, NTP_V0_INST_SIZE=7,
       NTP_V2_INST_SIZE=15, NTP_MAX_INST=63 };
enum { NTP_NOTE_ONESHOT=0, NTP_NOTE_LOOP=1, NTP_NOTE_HEADER=2,
       NTP_NOTE_SUSTAIN=3 };
typedef struct {
    uint32_t len; /* v2 stores 24-bit lengths; reject oversized data safely */
    uint8_t kind, volume, finetune, page, size;
} ntp_inst_t;
static const uint16_t period_by_note[72]={
    1712,1616,1525,1440,1357,1281,1209,1141,1077,1017,961,907,
    856,808,762,720,678,640,604,570,538,508,480,453,
    428,404,381,360,339,320,302,285,269,254,240,226,
    214,202,190,180,170,160,151,143,135,127,120,113,
    107,101,95,90,85,80,76,71,67,64,60,57,
    53,50,47,45,42,40,37,35,33,31,30,28
};
static uint8_t is_legal_rts(uint8_t v)
{
    for(unsigned i=0;i<8;i++)
        if(v==(uint8_t)(i*9u))return 1u;
    return 0u;
}
static uint8_t allowed_fx(uint8_t fx,uint8_t arg)
{
    if(fx<=6u || fx==10u || fx==11u || fx==12u ||
       fx==13u || fx==15u)return 1u;
    /* The first NTP experiment deliberately rejects effects that the
     * existing P2U interpreter would silently ignore or mis-render. */
    if(fx==14u) {
        const uint8_t sub=(uint8_t)(arg>>4);
        return sub==6u || sub==9u || sub==12u || sub==13u;
    }
    return 0u;
}
bool sensei_ntp_import(const uint8_t *src,size_t len,
                       uint8_t *pcm,size_t pcm_cap,
                       uint8_t *pat,size_t pat_cap,
                       sensei_ntp_decoded_t *out)
{
    ntp_inst_t inst[NTP_MAX_INST+1];
    uint8_t map[NTP_MAX_INST+1];
    uint8_t occupancy[256];
    size_t pos=NTP_HEADER, patterns_start, samples_start;
    unsigned ninst,npat,norder,logical=0,nonideal=0;
    uint8_t version;
    size_t max_end=0;
    if(!src || !out || len<NTP_HEADER+NTP_TRACKS ||
       memcmp(src,"nfc!",4)!=0 ||
       (src[4]!=0u && src[4]!=2u) ||
       src[5]!=NTP_TRACKS)return false;
    version=src[4];
    ninst=src[6];npat=src[7];norder=src[8];
    if(!ninst || ninst>NTP_MAX_INST || !npat || !norder || norder>128u ||
       (pcm==NULL)!=(pat==NULL))return false;
    /* Both versions carry already converted DOC waveforms. The 2022 v2
     * layout adds a title, track metadata, 24-bit lengths, repeat fields and
     * length-prefixed instrument names. Streaming remains out of scope. */
    memset(inst,0,sizeof(inst));
    memset(map,0,sizeof(map));
    memset(occupancy,0,sizeof(occupancy));
    memset(out,0,sizeof(*out));
    out->ntp_version=version;
    out->raw_instruments=(uint8_t)ninst;
    out->order_count=(uint8_t)norder;
    out->pattern_count=(uint8_t)npat;
    if(version==2u) {
        size_t name_len;
        if(pos>=len)return false;
        name_len=src[pos++];
        if(name_len>len-pos)return false;
        pos+=name_len; /* song name is metadata, not sound RAM */
    }
    if((size_t)NTP_TRACKS*(version==2u?3u:1u)>len-pos)return false;
    for(unsigned ch=0;ch<NTP_TRACKS;ch++) {
        const uint8_t ntp_output=src[pos];
        if(ntp_output>=8u)return false;
        if(version==2u) {
            /* v2: output channel, 512-byte stream-buffer DOC page,
             * original oscillators (bit 7 denotes a two-oscillator track).
             * We remap to four P2U voices, never reuse original osc IDs. */
            if(src[pos+1u]!=0u || (src[pos+2u]&0x7fu)>=31u)
                return false;
            pos+=3u;
        } else pos++;
        /* The original NinjaTrackerPlus 65816 copies output channel bits
         * directly into DOC CTRL[6:4] (ntp_output << 4). Output 0 is
         * left, output 1 is right. Our HDMI path is stereo only: retain
         * that bit exactly while folding channels 2..7 by parity.
         * P2W mistakenly INVERTED the bit, reversing the NTP stereo image. */
        out->channel_pan[ch]=(uint8_t)((ntp_output&1u)<<4);
    }
    if((size_t)ninst*(version==2u?NTP_V2_INST_SIZE:NTP_V0_INST_SIZE)
       >len-pos)return false;
    for(unsigned i=1;i<=ninst;i++) {
        ntp_inst_t *q=&inst[i];
        size_t record_bytes=version==2u?NTP_V2_INST_SIZE:NTP_V0_INST_SIZE;
        if(record_bytes>len-pos)return false;
        q->kind=src[pos];
        if(version==2u) {
            size_t name_len=src[pos+14u];
            q->len=(uint32_t)src[pos+1u]|
                   ((uint32_t)src[pos+2u]<<8)|
                   ((uint32_t)src[pos+3u]<<16);
            /* repeat start/length at offsets 4..9 refer to the original
             * sample; DOC-ready split headers already contain the correct
             * attack and loop bytes in their own sample records. */
            q->volume=src[pos+10u];q->finetune=src[pos+11u];
            q->page=src[pos+12u];q->size=src[pos+13u];
            pos+=record_bytes;
            if(name_len>len-pos)return false;
            pos+=name_len;
        } else {
            q->len=(uint32_t)src[pos+1u]|
                   ((uint32_t)src[pos+2u]<<8);
            q->volume=src[pos+3u];q->finetune=src[pos+4u];
            q->page=src[pos+5u];q->size=src[pos+6u];
            pos+=record_bytes;
        }
        if(q->kind>7u || q->volume>64u ||
           q->finetune!=0u || !is_legal_rts(q->size) || !q->len)
            return false;
        if((q->kind&3u)==NTP_NOTE_SUSTAIN &&
           (i==1u || (inst[i-1].kind&3u)!=NTP_NOTE_HEADER))
            return false;
        if((q->kind&3u)==NTP_NOTE_HEADER &&
           (i>=ninst || pos>=len ||
            (src[pos]&3u)!=NTP_NOTE_SUSTAIN))
            return false;
    }
    if((size_t)norder>len-pos)return false;
    memcpy(out->orders,src+pos,norder);
    pos+=norder;
    for(unsigned i=0;i<norder;i++)
        if(out->orders[i]>=npat)return false;
    const size_t pat_bytes=(size_t)npat*256u*NTP_TRACKS;
    if(pat_bytes>SENSEI_NTP_MAX_PATTERN_BYTES ||
       pat_bytes>len-pos)return false;
    patterns_start=pos;
    pos+=pat_bytes;
    samples_start=pos;
    for(unsigned i=1;i<=ninst;i++) {
        const ntp_inst_t *q=&inst[i];
        const size_t dst=(size_t)q->page<<8;
        const size_t end=dst+q->len;
        if(end>SENSEI_NTP_MAX_WAVE_BYTES ||
           (size_t)q->len>len-pos)return false;
        /* NTP's DOC sample placement is explicit. Do NOT repack, resample,
         * remove zero terminators, xor 0x80, or recreate its loop bytes. */
        unsigned start_page=q->page;
        unsigned last_page=(unsigned)((end-1u)>>8);
        for(unsigned j=start_page;j<=last_page;j++) {
            if(occupancy[j])return false;
            occupancy[j]=1u;
        }
        if(pcm && end>pcm_cap)return false;
        pos+=q->len;
        if(end>max_end)max_end=end;
    }
    if(pos!=len)return false; /* reject unsupported trailers or stray PCM */
    out->pcm_bytes=(uint32_t)((max_end+3u)&~(size_t)3u);
    out->pattern_bytes=(uint32_t)pat_bytes;
    if(out->pcm_bytes>SENSEI_NTP_MAX_WAVE_BYTES ||
       (pcm && out->pcm_bytes>pcm_cap) ||
       (pat && pat_bytes>pat_cap))return false;

    for(unsigned i=1;i<=ninst;i++) {
        const ntp_inst_t *q=&inst[i];
        const unsigned kind=q->kind&3u;
        if(kind==NTP_NOTE_SUSTAIN)continue;
        if(++logical>31u)return false;
        map[i]=(uint8_t)logical;
        uint8_t *d=&out->catalog[logical*8u];
        d[0]=q->page;d[1]=q->size;d[3]=q->volume;
        if(kind==NTP_NOTE_ONESHOT)
            d[2]=2u; /* DOC MODE_ONE_SHOT */
        else if(kind==NTP_NOTE_LOOP) {
            if(q->kind&4u)
                d[2]=0u; /* optimal loop: DOC MODE_FREE */
            else {
                d[2]=6u;d[4]=q->page;d[5]=q->size;
                d[6]=6u;d[7]=1u; /* two-way SWAP loop */
                ++nonideal;
            }
        } else if(kind==NTP_NOTE_HEADER) {
            const ntp_inst_t *loop=&inst[i+1u];
            d[2]=6u;  /* play head exactly once, then start loop partner */
            d[4]=loop->page;d[5]=loop->size;
            if(loop->kind&4u)d[6]=0u; /* ideal loop: free-running */
            else {d[6]=6u;++nonideal;} /* NTP IRQ loop handling not yet ported */
            d[7]=1u;
        } else return false;
    }
    out->logical_instruments=(uint8_t)logical;
    out->nonideal_pairs=(uint8_t)nonideal;

    /* Validate ALL note/effect records before touching a caller's output
     * buffers. Convert only score encoding, NOT waveform samples. */
    for(size_t k=0;k<pat_bytes;k+=4u) {
        const uint8_t *e=src+patterns_start+k;
        const unsigned note=e[0],instrument=e[1],fx=e[2],arg=e[3];
        if(note>72u || instrument>ninst ||
           (instrument && !map[instrument]) ||
           !allowed_fx((uint8_t)fx,(uint8_t)arg))
            return false;
    }
    if(!pcm)return true;
    memset(pcm,0x80,out->pcm_bytes);
    pos=samples_start;
    for(unsigned i=1;i<=ninst;i++) {
        const ntp_inst_t *q=&inst[i];
        memcpy(pcm+((size_t)q->page<<8),src+pos,q->len);
        pos+=q->len;
    }
    for(size_t k=0;k<pat_bytes;k+=4u) {
        const uint8_t *e=src+patterns_start+k;
        const uint16_t period=e[0]?period_by_note[e[0]-1u]:0u;
        const uint8_t instrument=e[1]?map[e[1]]:0u;
        pat[k]=(uint8_t)((instrument&0xF0u)|((period>>8)&15u));
        pat[k+1u]=(uint8_t)period;
        pat[k+2u]=(uint8_t)((instrument<<4)|(e[2]&15u));
        pat[k+3u]=e[3];
    }
    return true;
}
