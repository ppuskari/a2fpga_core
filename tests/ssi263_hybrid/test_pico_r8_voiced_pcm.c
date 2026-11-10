/* R8 voiced-noise oscillator: same phoneme/control sequence in original and
 * fast-cos builds. Both print raw LE PCM16 to stdout for sample-wise parity.
 * This tests synthesis math, not any A2 bus or FPGA timing. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "ssi263.h"

int main(void)
{
    ssi263_params p;
    ssi263_default_params(&p);
    p.xck_hz=1020000.0f;
    if(p.noise_voice_swell==0.0f) {
        fprintf(stderr,"ERROR: default voiced noise swell is disabled\n");
        return 8;
    }
    ssi263 *c=ssi263_new(&p,ssi263_default_rom(),22050.0f);
    if(!c)return 2;
    ssi263_write(c,4,0xe8);
    ssi263_write(c,2,0xa8);
    ssi263_write(c,1,0x6f);
    ssi263_write(c,0,0x60);
    ssi263_write(c,3,0x7f);
    static const unsigned char phonemes[12]={
        0x60,0x62,0x68,0x30,0x76,0x20,0x5c,0x7f,0x6d,0x33,0x71,0x42
    };
    unsigned long maxabs=0;
    clock_t start=clock();
    for(int block=0;block<384;block++) {
        if((block%32)==0)
            ssi263_write(c,0,phonemes[(block/32)%12]);
        real out[128];
        short pcm[128];
        if(ssi263_run(c,128,out)!=128)return 3;
        ssi_pcm16(out,128,p.output_gain,pcm);
        for(int i=0;i<128;i++) {
            int32_t v=pcm[i];
            unsigned long ab=(unsigned long)(v<0?-v:v);
            if(ab>maxabs)maxabs=ab;
            unsigned char le[2]={(unsigned char)(uint16_t)v,
                                 (unsigned char)((uint16_t)v>>8)};
            if(fwrite(le,1,2,stdout)!=2)return 4;
        }
    }
    fprintf(stderr,"Pico R8 voiced fixture CPU_seconds=%.3f maxPCM=%lu\n",
            (double)(clock()-start)/CLOCKS_PER_SEC,maxabs);
    ssi263_free(c);
    return maxabs ? 0 : 5;
}
