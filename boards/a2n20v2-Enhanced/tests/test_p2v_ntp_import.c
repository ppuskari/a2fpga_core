/*
 * P2V: synthetic NTP v0 file conforming to the original Ninjaforce
 * ntpconverter_lib.php layout. No copyrighted tracker samples included.
 */
#include "sensei_ntp_import.h"
#include "sensei_mod_player.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
enum {NINST=3, NPAT=1, FILE_SIZE=9+4+7*NINST+1+1024+8+512+8};
static uint8_t file[FILE_SIZE],pat[1024],pcm[4096];
static sensei_ntp_decoded_t decoded;
static unsigned events,starts;
static uint8_t first_ctrl;
static void require(int ok,const char *msg)
{
    if(!ok){fprintf(stderr,"FAIL P2V: %s\n",msg);exit(1);}
}
static void send_event(uint16_t ms,uint8_t addr,uint8_t data)
{
    (void)ms;
    ++events;
    if(addr==0xA0u && !(data&1u)){
        ++starts;first_ctrl=data;
    }
}
static void inst(unsigned offset,uint8_t type,uint16_t bytes,
                 uint8_t vol,uint8_t page,uint8_t rts)
{
    file[offset]=type;
    file[offset+1]=(uint8_t)bytes;
    file[offset+2]=(uint8_t)(bytes>>8);
    file[offset+3]=vol;
    file[offset+4]=0; /* finetune */
    file[offset+5]=page;
    file[offset+6]=rts;
}
static void fixture(void)
{
    memcpy(file,"nfc!",4);
    file[4]=0;file[5]=4;file[6]=NINST;file[7]=NPAT;file[8]=1;
    file[9]=1;file[10]=0;file[11]=0;file[12]=1;
    inst(13,2,8,56,0,0);    /* attack header */
    inst(20,7,512,56,2,9);  /* ideal sustain */
    inst(27,0,8,42,4,0);    /* one-shot */
    file[34]=0; /* pattern order 0 */
    unsigned p=35;
    file[p+0]=25;file[p+1]=1;file[p+2]=4;file[p+3]=0x47;
    file[p+4]=25;file[p+5]=3;file[p+6]=0;file[p+7]=0;
    unsigned sound=p+1024;
    const uint8_t attack[8]={0x80,0x90,0x01,0x7f,0x20,0x80,0x00,0x00};
    memcpy(file+sound,attack,8);
    for(unsigned i=0;i<512;i++)
        file[sound+8+i]=(uint8_t)(i&0xffu);
    const uint8_t one_shot[8]={1,2,3,4,0x00,0x00,0x00,0x00};
    memcpy(file+sound+520,one_shot,8);
}
int main(void)
{
    fixture();
    require(sensei_ntp_import(file,sizeof file,NULL,0,NULL,0,&decoded),
            "dry-run parser rejected original v0 format");
    require(decoded.pattern_bytes==1024 &&
            decoded.pcm_bytes==1032 &&
            decoded.logical_instruments==2u &&
            decoded.nonideal_pairs==0u,"incorrect size and pair count");
    require(decoded.channel_pan[0]==0u && decoded.channel_pan[1]==0x10u &&
            decoded.channel_pan[2]==0x10u && decoded.channel_pan[3]==0u,
            "explicit NTP stereo assignments");
    require(decoded.catalog[8+0]==0u &&
            decoded.catalog[8+1]==0u &&
            decoded.catalog[8+2]==6u &&
            decoded.catalog[8+3]==56u &&
            decoded.catalog[8+4]==2u &&
            decoded.catalog[8+5]==9u &&
            decoded.catalog[8+6]==0u &&
            decoded.catalog[8+7]==1u,
            "NTP header/ideal sustain mapping incorrect");
    require(decoded.catalog[16+0]==4u &&
            decoded.catalog[16+2]==2u &&
            decoded.catalog[16+3]==42u,
            "NTP one-shot metadata mapping incorrect");
    memset(pcm,0xCE,sizeof pcm);memset(pat,0xCE,sizeof pat);
    require(sensei_ntp_import(file,sizeof file,pcm,sizeof pcm,
                              pat,sizeof pat,&decoded),
            "second pass rejected NTP");
    require(!memcmp(pcm,file+1059,8),
            "NTP attack bytes MUST NOT be transformed");
    require(!memcmp(pcm+512,file+1067,512),
            "NTP sustain bytes MUST NOT be transformed");
    require(!memcmp(pcm+1024,file+1579-8,8),
            "NTP one-shot bytes MUST NOT be transformed");
    require(pcm[2]==0x01 && pcm[6]==0x00 &&
            pcm[512]==0x00 && pcm[513]==0x01,
            "retain both sample-zero terminators and converted NTP PCM");
    require(pcm[8]==0x80 && pcm[511]==0x80,
            "nonoccupied DOC pages must be silent offset-binary");
    require(pat[0]==0x01 && pat[1]==0xAC &&
            pat[2]==0x14 && pat[3]==0x47,
            "NTP note25 must map to MOD period428 while preserving effect");
    require(pat[4]==0x01 && pat[5]==0xAC &&
            pat[6]==0x20 && pat[7]==0x00,
            "NTP instrument3 should map to second logical sample");

    sensei_mod_player_t player;
    require(sensei_mod_init_runtime(&player,pat,decoded.orders,
                                    decoded.order_count,decoded.catalog,100),
            "could not initialize P2U tracker from NTP patterns");
    memcpy(player.channel_pan,decoded.channel_pan,4);
    require(sensei_mod_tick(&player,send_event),"real tick0 failed");
    require(events==21u && starts==1u && first_ctrl==6u,
            "NTP two DOC note starts not executed with expected channel");
    puts("PASS P2V: original v0 DOC PCM is byte-exact, no wave recoding");
    puts("PASS P2V: NTP attack+ideal-sustain and one-shot metadata and panning");
    puts("PASS P2V: raw NTP pattern events execute in existing C tick engine");

    file[4]=1;
    require(!sensei_ntp_import(file,sizeof file,NULL,0,NULL,0,&decoded),
            "must reject NTP newer version before upload");
    file[4]=0;
    file[35+2]=7; /* unsupported tremolo in P2U first-pass engine */
    require(!sensei_ntp_import(file,sizeof file,NULL,0,NULL,0,&decoded),
            "must reject unsupported effects, not silently ignore");
    file[35+2]=4;
    require(!sensei_ntp_import(file,sizeof file-1,NULL,0,NULL,0,&decoded),
            "must reject incomplete samples");
    puts("PASS P2V: reject unsafe versions, unsupported effects and truncation");
    return 0;
}
