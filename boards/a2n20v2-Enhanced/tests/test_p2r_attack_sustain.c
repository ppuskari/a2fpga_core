/*
 * Sensei P2R attack/sustain DOC SWAP regression.
 * Synthesizes original 15k-like instrument lengths/loops, NOT copyrighted PCM.
 * Uses production MOD runtime decoder and production BL616 tracker engine.
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "sensei_mod_decode.h"
#include "sensei_mod_player.h"

enum { ATTACK1=814, LOOP1=128, ATTACK15=862, LOOP15=128,
       SAMPLE1=ATTACK1+LOOP1, SAMPLE15=ATTACK15+LOOP15 };
static uint8_t modfile[1084+1024+SAMPLE1+SAMPLE15];
static uint8_t pcm[49152];
static sensei_mod_decoded_t decoded;
typedef struct {uint16_t time;uint8_t reg,data;} event_t;
static event_t events[128];
static unsigned count;
static void emit(uint16_t t,uint8_t r,uint8_t v)
{
    if(count>=128) {fputs("Too many events\n",stderr);exit(1);}
    events[count++]=(event_t){t,r,v};
}
static void require(int cond,const char *why)
{
    if(!cond){fprintf(stderr,"FAIL P2R: %s\n",why);exit(1);}
}
static void def_inst(unsigned inst,unsigned length,unsigned loop_at,
                     unsigned loop_len,unsigned volume)
{
    size_t base=20u+30u*(inst-1u);
    modfile[base+22]=(uint8_t)(length/2u>>8);
    modfile[base+23]=(uint8_t)(length/2u);
    modfile[base+25]=(uint8_t)volume;
    modfile[base+26]=(uint8_t)(loop_at/2u>>8);
    modfile[base+27]=(uint8_t)(loop_at/2u);
    modfile[base+28]=(uint8_t)(loop_len/2u>>8);
    modfile[base+29]=(uint8_t)(loop_len/2u);
}
static uint8_t encoded(uint8_t v)
{
    uint8_t x=(uint8_t)(v^0x80u);
    return x?x:1u;
}
static void check_ctrl(uint8_t reg,uint8_t last)
{
    int found=-1;
    for(unsigned i=0;i<count;i++) if(events[i].reg==reg) found=(int)i;
    require(found>=0 && events[found].data==last,"wrong DOC control mode / panning");
}
static void test_parser(void)
{
    const size_t sample_pos=1084u+1024u;
    uint8_t *s1=modfile+sample_pos;
    uint8_t *s15=s1+SAMPLE1;
    memcpy(modfile+1080,"M.K.",4);
    modfile[950]=1;
    def_inst(1,SAMPLE1,ATTACK1,LOOP1,64);
    def_inst(15,SAMPLE15,ATTACK15,LOOP15,64);
    for(unsigned i=0;i<SAMPLE1;i++)
        s1[i]=(uint8_t)(i*11u+17u);
    for(unsigned i=0;i<SAMPLE15;i++)
        s15[i]=(uint8_t)(i*7u+37u);

    require(sensei_mod_decode(modfile,sizeof modfile,NULL,0,&decoded),
            "dry-run incorrectly rejects two-stage MOD");
    require(decoded.doc_pcm_bytes==3328u,"DOC bank size/align for two splits");
    require(sensei_mod_decode(modfile,sizeof modfile,pcm,
                              decoded.doc_pcm_bytes,&decoded),
            "actual decode differs from dry-run");
    const uint8_t *a=decoded.catalog+8; /* instrument 1 */
    const uint8_t *b=decoded.catalog+15u*8u;
    require(a[0]==0 && a[1]==0x12 && a[2]==6 && a[3]==64 &&
            a[4]==4 && a[5]==0 && a[6]==0 && a[7]==1,
            "instrument 1 attack/sustain metadata");
    require(b[0]==8 && b[1]==0x12 && b[2]==6 && b[3]==64 &&
            b[4]==12 && b[5]==0 && b[6]==0 && b[7]==1,
            "instrument 15 attack/sustain metadata");
    require(pcm[0]==encoded(s1[0]) &&
            pcm[ATTACK1-1]==encoded(s1[ATTACK1-1]) &&
            pcm[ATTACK1]==0,
            "instrument1 attack was replaced or sentinel misplaced");
    for(unsigned j=0;j<256;j++)
        require(pcm[1024u+j]==encoded(s1[ATTACK1+j%LOOP1]),
                "instrument1 sustain loop has padded silence");
    require(pcm[2048u]==encoded(s15[0]) &&
            pcm[2048u+ATTACK15-1u]==encoded(s15[ATTACK15-1u]) &&
            pcm[2048u+ATTACK15]==0,
            "instrument15 attack or transition incorrect");
    for(unsigned j=0;j<256;j++)
        require(pcm[3072u+j]==encoded(s15[ATTACK15+j%LOOP15]),
                "instrument15 sustain loop has padded silence");
    puts("PASS P2R: full 814/862-byte attacks, sentinel at loop starts, sustain repeated");
}
static void test_playback(void)
{
    sensei_mod_player_t s;
    const uint8_t orders[1]={0};
    const uint8_t *rows=modfile+1084;
    /* 4 simultaneous 428-period notes; left=ch0/3, right=ch1/2.
       Note conversion and paired event emission happen at runtime. */
    for(unsigned ch=0;ch<4;ch++) {
        unsigned inst=(ch==3)?15u:1u;
        size_t i=1084u+ch*4u;
        modfile[i]=(uint8_t)((inst&0xF0u)|1u);
        modfile[i+1]=0xAC;
        modfile[i+2]=(uint8_t)((inst&15u)<<4);
    }
    require(sensei_mod_init_runtime(&s,rows,orders,1,decoded.catalog,200),
            "runtime tracker init");
    require(sensei_mod_tick(&s,emit),"runtime tick0 failed");
    require(count>=52u && count<=64u,"4 note-ons must fit 64-event FPGA FIFO");
    for(unsigned ch=0;ch<4;ch++) {
        uint8_t first=(uint8_t)(ch*2u),second=(uint8_t)(first+1u);
        uint8_t pan=(ch==1u || ch==2u)?0x10u:0;
        check_ctrl((uint8_t)(0xA0u+first),(uint8_t)(pan|6u));
        check_ctrl((uint8_t)(0xA0u+second),(uint8_t)(pan|1u));
    }
    require(events[0].time==300u,"unexpected attack start time");
    count=0;
    /* Axx should update volume on BOTH paired oscillators. */
    modfile[1084u+16u+2u]=0x0A;
    modfile[1084u+16u+3u]=0x01;
    for(unsigned i=1;i<7;i++)
        require(sensei_mod_tick(&s,emit),"runtime tick failed");
    int v0=0,v1=0;
    for(unsigned i=0;i<count;i++) {
        if(events[i].reg==0x40)v0++;
        if(events[i].reg==0x41)v1++;
    }
    require(v0>0 && v1>0,"volume slide not mirrored to sustain");
    puts("PASS P2R: four DOC oscillator pairs, correct channel pan, effects on both phases");
}
int main(void) {
    test_parser();
    test_playback();
    return 0;
}
