/* Real public-domain HxCMOD C engine, synthetic ProTracker MOD fixture.
 * Validates stereo PCM extraction without Ensoniq, IIgs or FPGA events. */
#include "hxcmod.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint8_t mod[1084+1024+128];
static modcontext ctx;
static msample pcm[2*2048];
static void check(int cond,const char *msg)
{
    if(!cond){fprintf(stderr,"FAIL HxCMOD: %s\n",msg);exit(1);}
}
int main(void)
{
    memset(mod,0,sizeof mod);
    memcpy(mod,"MCU PCM 44100",13);
    mod[20+22]=0;mod[20+23]=64; // sample 1: 64 words (128 bytes)
    mod[20+25]=64; // volume
    mod[950]=1;    // song order length
    memcpy(mod+1080,"M.K.",4);
    // 4ch, first row CH0 C-3 period 428 with sample #1
    mod[1084]=0x01;mod[1085]=0xAC;
    mod[1086]=0x10;mod[1087]=0x00;
    for(unsigned i=0;i<128u;i++)
        mod[1084+1024+i]=(uint8_t)(i<64?i*2u:255u-(i-64u)*2u);
    check(hxcmod_init(&ctx),"initialization");
    check(hxcmod_setcfg(&ctx,44100,100,1),"44.1k configure");
    check(hxcmod_load(&ctx,mod,sizeof mod),"load synthetic 4ch MOD");
    memset(pcm,0,sizeof pcm);
    hxcmod_fillbuffer(&ctx,pcm,2048,NULL);
    unsigned left=0,right=0,nonzero=0;
    for(unsigned i=0;i<2048;i++){
        if(pcm[2u*i])left++;
        if(pcm[2u*i+1u])right++;
        if(pcm[2u*i] || pcm[2u*i+1u])nonzero++;
    }
    check(nonzero>500u,"render generated silence");
    check(left>500u && right>500u,"stereo PCM channels missing");
    hxcmod_unload(&ctx);
    printf("PASS MCU MOD: HxCMOD loads original ProTracker fixture and emits %u nonzero stereo frames\n",nonzero);
    return 0;
}
