/* P10-R4 evaluate impact of -fsingle-precision-constant on pinned Pico
 * reference PCM, across a reproducible sequence of real SSI register writes.
 * This test does NOT prove BL616 performance; it only checks acoustic
 * deviations at compile precision. The output is signed PCM16LE binary. */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "ssi263.h"
int main(void)
{
    ssi263_params p;
    ssi263_default_params(&p);
    p.xck_hz=1020000.0f;
    ssi263 *c=ssi263_new(&p,ssi263_default_rom(),44100.0f);
    if(!c)return 2;
    ssi263_write(c,4,0xe8);
    ssi263_write(c,2,0xa8);
    ssi263_write(c,1,0x6f);
    ssi263_write(c,3,0x7f);
    uint32_t checksum=0;
    for(int block=0;block<96;block++) {
        if((block%12)==0) {
            static const unsigned char phonemes[8]={0x60,0x62,0x68,0x30,0x76,0x20,0x5c,0x7f};
            ssi263_write(c,0,phonemes[block/12]);
        }
        real f[128];
        short out[128];
        if(ssi263_run(c,128,f)!=128)return 3;
        ssi_pcm16(f,128,p.output_gain,out);
        for(int i=0;i<128;i++) {
            uint16_t v=(uint16_t)out[i];
            unsigned char bytes[2]={(uint8_t)v,(uint8_t)(v>>8)};
            if(fwrite(bytes,1,2,stdout)!=2)return 4;
            checksum+=(uint32_t)(uint16_t)out[i];
        }
    }
    ssi263_free(c);
    (void)checksum;
    return 0;
}
