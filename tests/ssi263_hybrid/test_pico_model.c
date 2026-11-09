#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include "ssi263.h"
int main(void) {
    ssi263_params p;
    ssi263_default_params(&p);
    p.xck_hz=1020000.0f;
    ssi263 *c=ssi263_new(&p,ssi263_default_rom(),44100.0f);
    assert(c);
    ssi263_write(c,4,0xe8);
    ssi263_write(c,2,0xa8);
    ssi263_write(c,1,0x6f);
    ssi263_write(c,0,0x60);
    ssi263_write(c,3,0x7f);
    real out[257];
    short samples[257];
    long got=ssi263_run(c,256,out);
    assert(got==256);
    ssi_pcm16(out,256,p.output_gain,samples);
    long absmax=0;
    for(int i=0;i<256;i++) {
        long v=samples[i];
        if(v<0)v=-v;
        if(v>absmax)absmax=v;
    }
    assert(absmax>0);
    ssi263_write(c,3,0x80);
    ssi263_free(c);
    printf("PASS: pinned Pico-C BL616 model 256 samples, peak %ld PCM units\n",absmax);
    return 0;
}
