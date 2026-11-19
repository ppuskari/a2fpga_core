/* P2W: synthetic NTP v2 fixture with modern metadata, no copyrighted PCM.
 * The two online NinjaForce converter files are not distributed in the repo.
 * Format cross-checked against v2 ntpconverter.c and converter output. */
#include "sensei_ntp_import.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    FILE_BYTES=1326, TRACK_OFF=14, INST_OFF=26,
    ORDER_OFF=45, PAT_OFF=46, PCM_OFF=1070
};
static uint8_t ntp[FILE_BYTES],pcm[2048],pattern[1024];
static sensei_ntp_decoded_t decoded;

static void require(int yes, const char *what)
{
    if(!yes) {
        fprintf(stderr,"FAIL P2W: %s\n",what);
        exit(1);
    }
}
static void fixture(void)
{
    memset(ntp,0,sizeof ntp);
    memcpy(ntp,"nfc!",4);
    ntp[4]=2;ntp[5]=4;ntp[6]=1;ntp[7]=1;ntp[8]=1;
    ntp[9]=4;memcpy(ntp+10,"demo",4);
    /* Four v2 (output, stream buffer, oscillator allocation) tuples.
     * 0x80 means the original player used an oscillator pair. */
    const uint8_t tracks[12]={1,0,0x80, 0,0,2, 0,0,4, 1,0,6};
    memcpy(ntp+TRACK_OFF,tracks,sizeof tracks);
    /* Instrument: ideal one-shot, 256-byte DOC-ready wave at page 0.
     * v2: type(1), length(3), repeat-start(3), repeat-size(3),
     * volume, finetune, DOC page, DOC RTS, name length/name. */
    ntp[INST_OFF]=4;
    ntp[INST_OFF+1]=0;ntp[INST_OFF+2]=1;ntp[INST_OFF+3]=0;
    ntp[INST_OFF+7]=2; /* repeat length, from original MOD metadata */
    ntp[INST_OFF+10]=64;ntp[INST_OFF+11]=0;
    ntp[INST_OFF+12]=0;ntp[INST_OFF+13]=0;
    ntp[INST_OFF+14]=4;memcpy(ntp+INST_OFF+15,"tone",4);
    ntp[ORDER_OFF]=0;
    ntp[PAT_OFF]=25;ntp[PAT_OFF+1]=1;
    ntp[PAT_OFF+2]=4;ntp[PAT_OFF+3]=0x47;
    for(unsigned i=0;i<256;i++)
        ntp[PCM_OFF+i]=(uint8_t)(1u+(i%254u));
    ntp[PCM_OFF]=0x80;ntp[PCM_OFF+3]=0x01;
}
int main(void)
{
    fixture();
    require(sensei_ntp_import(ntp,sizeof ntp,NULL,0,NULL,0,&decoded),
            "v2 metadata dry run");
    require(decoded.ntp_version==2u && decoded.order_count==1u &&
            decoded.raw_instruments==1u && decoded.logical_instruments==1u,
            "NTP v2 header fields");
    require(decoded.pattern_bytes==1024u && decoded.pcm_bytes==256u,
            "NTP v2 offsets and lengths");
    require(decoded.channel_pan[0]==0x10u &&
            decoded.channel_pan[1]==0u &&
            decoded.channel_pan[2]==0u &&
            decoded.channel_pan[3]==0x10u, "v2 original NTP stereo parity");
    /* Non-front NTP outputs still downmix by documented parity. */
    ntp[TRACK_OFF]=2u;ntp[TRACK_OFF+3u]=3u;
    require(sensei_ntp_import(ntp,sizeof ntp,NULL,0,NULL,0,&decoded) &&
            decoded.channel_pan[0]==0u && decoded.channel_pan[1]==0x10u,
            "v2 surround left/right stereo parity");
    ntp[TRACK_OFF]=1u;ntp[TRACK_OFF+3u]=0u;
    require(sensei_ntp_import(ntp,sizeof ntp,NULL,0,NULL,0,&decoded),
            "v2 restore original stereo fixture");
    require(decoded.catalog[8]==0u && decoded.catalog[9]==0u &&
            decoded.catalog[10]==2u && decoded.catalog[11]==64u,
            "original DOC page/RTS/mode/volume");
    memset(pcm,0xCE,sizeof pcm);
    memset(pattern,0xCE,sizeof pattern);
    require(sensei_ntp_import(ntp,sizeof ntp,pcm,sizeof pcm,
                              pattern,sizeof pattern,&decoded),
            "v2 copy stage");
    require(!memcmp(pcm,ntp+PCM_OFF,256),
            "keep modern converter DOC samples byte-for-byte");
    require(pattern[0]==0x01u && pattern[1]==0xACu &&
            pattern[2]==0x14u && pattern[3]==0x47u,
            "translate v2 pattern to original ProTracker period/effect");
    puts("PASS P2W: NinjaTrackerPlus v2 metadata and DOC PCM are byte exact");

    ntp[TRACK_OFF+1]=4;
    require(!sensei_ntp_import(ntp,sizeof ntp,NULL,0,NULL,0,&decoded),
            "must reject streamed track allocation");
    ntp[TRACK_OFF+1]=0;
    ntp[INST_OFF]=8;
    require(!sensei_ntp_import(ntp,sizeof ntp,NULL,0,NULL,0,&decoded),
            "must reject streamed sample kind");
    ntp[INST_OFF]=4;
    ntp[INST_OFF+11]=0xF8;
    require(!sensei_ntp_import(ntp,sizeof ntp,NULL,0,NULL,0,&decoded),
            "must reject nonzero finetune");
    ntp[INST_OFF+11]=0;
    ntp[PAT_OFF+2]=7;
    require(!sensei_ntp_import(ntp,sizeof ntp,NULL,0,NULL,0,&decoded),
            "must reject unsupported tracker effect");
    ntp[PAT_OFF+2]=4;
    ntp[TRACK_OFF]=8;
    require(!sensei_ntp_import(ntp,sizeof ntp,NULL,0,NULL,0,&decoded),
            "must reject invalid output channel");
    ntp[TRACK_OFF]=1;
    require(!sensei_ntp_import(ntp,sizeof ntp-1,NULL,0,NULL,0,&decoded),
            "must reject truncated DOC waveform");
    ntp[4]=1;
    require(!sensei_ntp_import(ntp,sizeof ntp,NULL,0,NULL,0,&decoded),
            "must not misparse v1 as v0 or v2");
    puts("PASS P2W: streamed, finetune, effect, channel, truncated and v1 rejections");
    return 0;
}
