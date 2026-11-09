/* C reference speech trace: same register/timing script as P8B RTL.
 * Independent validation using pinned MIT Mockingboard Pico engine.
 * Output raw signed PCM16 LE mono at 50 kHz.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "ssi263.h"

static void emit(ssi263 *c, FILE *out, const ssi263_params *p, int n) {
    float buffer[500];
    int16_t pcm[500];
    while (n>0) {
        int take=n>500?500:n;
        long got=ssi263_run(c,take,buffer);
        if (got!=take) {fprintf(stderr,"short C run %ld\n",got);exit(3);}
        ssi_pcm16(buffer,take,p->output_gain,pcm);
        for (int k=0;k<take;k++) {
            unsigned u=(unsigned)(uint16_t)pcm[k];
            if (fputc(u&255,out)==EOF || fputc((u>>8)&255,out)==EOF)
                exit(4);
        }
        n-=take;
    }
}

int main(int argc,char **argv) {
    if(argc<2) return 2;
    FILE *out=fopen(argv[1],"wb");
    if(!out) return 2;
    ssi263_params p;
    ssi263_default_params(&p);
    p.xck_hz=1000000.0;
    p.output_oversample=1.0;
    ssi263 *c=ssi263_new(&p,ssi263_default_rom(),50000.0);
    if(!c) return 2;
    /* R4 E8 gives fc=1MHz/(2*(256-232))=20833Hz. */
    ssi263_write(c,4,0xe8);
    ssi263_write(c,2,0xa8);
    ssi263_write(c,1,0x6f);
    ssi263_write(c,0,0x60);
    ssi263_write(c,3,0x7f);
    emit(c,out,&p,2500);
    ssi263_write(c,0,0x88);
    emit(c,out,&p,2500);
    ssi263_write(c,0,0x44);
    emit(c,out,&p,2500);
    ssi263_write(c,3,0x80);
    fclose(out);ssi263_free(c);
    puts("PASS: pinned Pico SSI263 reference, 3 x 50 ms phoneme trace");
    return 0;
}
