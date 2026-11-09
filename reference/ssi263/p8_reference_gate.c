/* P8 full SSI-263 reference gate. This runs the exact pinned Pico C chip
 * model with the original Pico clean-room glottal source.
 * Reference ONLY; host executable, not synthesizable Verilog.
 */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdint.h>
#include "ssi263.h"

static const float clean_glottal[] = {
  .750000f, .000632f, .002476f, .005384f, .009119f,
  .013378f, .017818f, .022078f, .025813f, .028721f,
  .030565f, .031197f, .028822f, .022059f, .011938f
};
static void demand(int yes, const char *msg) {
    if (!yes) { fprintf(stderr,"FAIL: %s\n",msg); exit(2); }
}
int main(int argc,char **argv) {
    const char *out_path = argc > 1 ? argv[1] : "p8_ref_voice.pcm";
    FILE *f = fopen(out_path,"wb");
    demand(f != NULL,"open output PCM");
    ssi263_params p;
    ssi263_default_params(&p);
    p.xck_hz = 1020000.0f;
    p.output_oversample = 1.0f;
    p.glottal_n = (real)(sizeof clean_glottal/sizeof clean_glottal[0]);
    for (unsigned i=0;i<sizeof clean_glottal/sizeof clean_glottal[0];i++)
        p.glottal_wave[i] = clean_glottal[i];
    const unsigned char *rom = ssi263_default_rom();
    demand(rom != NULL,"decoded ROM");
    ssi263 *c=ssi263_new(&p,rom,50000.0f);
    demand(c != NULL,"build chip");
    demand(ssi263_reg(c,3)==0x80,"CTL powerdown at reset");
    demand(ssi263_request(c)==0,"A/R low at reset");
    /* Representative real Mockingboard Demo Disk startup plus three
       distinct phonemes: register transaction protocol is held constant. */
    ssi263_write(c,3,0x80);
    ssi263_write(c,0,0xC0);
    ssi263_write(c,3,0x70);
    demand(ssi263_reg(c,3)==0x70,"CTL power-up");
    const int words[][5] = {
        {0xE8,0x7F,0xA8,0x6F,0x60},
        {0xE8,0x6E,0xA8,0x63,0x88},
        {0xE8,0x5D,0xA8,0x5B,0x44},
        {0xE8,0x7F,0xA8,0x6F,0x60},
        {0xE8,0x7F,0xA8,0x6F,0x60}
    };
    float buf[512];
    int16_t pcm[512];
    double peak=0.0, sumsq=0.0;
    uint64_t total=0;
    for(unsigned n=0;n<sizeof words/sizeof words[0];n++) {
        for(int reg=4;reg>=0;reg--) ssi263_write(c,reg,words[n][4-reg]);
        demand((ssi263_reg(c,0)&0x3f)==(words[n][4]&0x3f),"R0 latch");
        for(int k=0;k<60;k++) {
            long made=ssi263_run(c,512,buf);
            demand(made==512,"fixed samples per call");
            ssi_pcm16(buf,512,p.output_gain,pcm);
            demand(fwrite(pcm,sizeof pcm[0],512,f)==512,"write raw PCM");
            for(int i=0;i<512;i++) {
                double a=fabs((double)pcm[i]); if(a>peak)peak=a;
                sumsq+=(double)pcm[i]*pcm[i];
            }
            total+=512;
        }
    }
    ssi263_write(c,3,0x80);
    demand(ssi263_request(c)==0,"A/R low on powerdown");
    demand(total>100000 && peak>0,"nonzero voice output");
    fclose(f);
    printf("PASS: SSI263 pinned C reference, pcm16=%llu samples peak=%g rms=%g, A/R/CTL/ROM OK\n",
           (unsigned long long)total,peak/32768.0,sqrt(sumsq/(double)total)/32768.0);
    ssi263_free(c);
    return 0;
}
