/* J2R3: live gain stage protects -2 dBFS sample peak at any track level. */
#include "mcu_mod_gain.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void check(int yes,const char *msg)
{
    if(!yes){fprintf(stderr,"FAIL GAIN: %s\n",msg);exit(1);}
}
static int iabs(int x){return x<0?-x:x;}
int main(void)
{
    int16_t pcm[512];
    check(mod_gain_get_db()==MOD_GAIN_DEFAULT_DB,"default not +8 dB");
    mod_gain_reset();
    for(unsigned i=0;i<256;i++){
        pcm[2*i]=1000;
        pcm[2*i+1]=-500;
    }
    mod_gain_apply(pcm,256);
    check(iabs(pcm[0]-2512)<=3,"+8 dB linear gain incorrect");
    check(iabs(pcm[1]+1256)<=3,"stereo balance changed");
    check(pcm[0]==pcm[510] && pcm[1]==pcm[511],
          "gain drift within a block");
    mod_gain_reset();
    for(unsigned i=0;i<256;i++){
        pcm[2*i]=32000;
        pcm[2*i+1]=-32768;
    }
    mod_gain_apply(pcm,256);
    for(unsigned i=0;i<512;i++)
        check(iabs((int)pcm[i])<=MOD_GAIN_CEILING,
              "peak exceeded -2 dBFS PCM ceiling");
    check(pcm[0]>24000 && pcm[1]<-24000,
          "peak limiter attenuated stereo too far");
    mod_gain_set_db(0);
    mod_gain_reset();
    for(unsigned i=0;i<512;i++)pcm[i]=(i&1)?-1000:1000;
    mod_gain_apply(pcm,256);
    check(pcm[0]==1000 && pcm[1]==-1000,"0dB not unity");
    mod_gain_set_db(100);
    check(mod_gain_get_db()==MOD_GAIN_MAX_DB,"max gain not clamped");
    mod_gain_set_db(8);
    mod_gain_reset();
    puts("PASS J2R3: +8dB stereo headroom gain, live 0..12dB controls, -2dBFS ceiling");
    return 0;
}
