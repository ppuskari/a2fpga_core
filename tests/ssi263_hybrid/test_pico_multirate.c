#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include "ssi263.h"
/* Chip XCK and phoneme timing remain constant as only the PCM rate changes.
 * Verify native Pico engine provides nonzero, finite audio at all rates. */
int main(void)
{
    const int rates[3] = {44100,22050,11025};
    for (int k=0; k<3; k++) {
        ssi263_params p;
        ssi263_default_params(&p);
        p.xck_hz=1020000.0f;
        ssi263 *c=ssi263_new(&p,ssi263_default_rom(),(real)rates[k]);
        assert(c);
        ssi263_write(c,4,0xe8);
        ssi263_write(c,2,0xa8);
        ssi263_write(c,1,0x6f);
        ssi263_write(c,0,0x60);
        ssi263_write(c,3,0x7f);
        real out[257];
        short samples[257];
        for(int block=0;block<4;block++) {
            long got=ssi263_run(c,256,out);
            assert(got==256);
            ssi_pcm16(out,256,p.output_gain,samples);
            for (int i=0;i<256;i++) assert(isfinite(out[i]));
        }
        long maxabs=0;
        for(int i=0;i<256;i++) {
            long v=samples[i];
            if(v<0)v=-v;
            if(v>maxabs)maxabs=v;
        }
        assert(maxabs>0);
        printf("PASS Pico voice rate %dHz, last block PCM max %ld\n",rates[k],maxabs);
        ssi263_free(c);
    }
    return 0;
}
