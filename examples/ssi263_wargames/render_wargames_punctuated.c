/* Take 4B host preview (stronger word separation and the HQ film rising pitch) of the exact SSI-263 ROM phoneme bytes used by the
 * Apple II slot-4 WOPR-inspired demo. This synthesizes original PCM rather
 * than copying a copyrighted film soundtrack. 22.05k mono PCM16 WAV.
 *
 * Build:
 * gcc -std=c99 -O3 -fsingle-precision-constant -DSSI263_DIGITAL_NO_CARRIER=1 \
 *   -DSSI263_R8_FAST_SWELL=1 -Ireference/ssi263/pico-v1.0.1 \
 *   examples/ssi263_wargames/render_wargames_punctuated.c \
 *   reference/ssi263/pico-v1.0.1/ssi263.c \
 *   reference/ssi263/pico-v1.0.1/ssi263dsp.c -lm -o wargames_preview
 *
 * Run: ./wargames_preview wargames_ssi263_punctuated.wav
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ssi263.h"
#define SAMPLE_RATE 22050u
#define CHUNK 64
/* 45 frame score at R2=0x48, derived from 2.194s film recording. */
static const uint8_t phrase[]={
    0x72,0x4C,0x20,0x80, /* SHALL, clipped AE, 96ms pause */
    0xA3,0x41,0x80,      /* WE, clipped E, 96ms pause */
    0xE7,0xA0,0x45,0x80, /* PLAY, clipped AY, 96ms pause */
    0x4E,0x80,           /* A, clipped AH, 96ms pause */
    0x66,0x05,0x37,0x80  /* GAME, full end rise and nasal M */
};

static void le16(FILE *f,uint32_t v) {
    fputc((int)(v & 255u),f);
    fputc((int)((v>>8)&255u),f);
}
static void le32(FILE *f,uint32_t v) {
    le16(f,v);
    le16(f,v>>16);
}
static int write_wav_header(FILE *f,uint32_t samples) {
    if(fseek(f,0,SEEK_SET))return -1;
    fwrite("RIFF",1,4,f);le32(f,36u+samples*2u);
    fwrite("WAVEfmt ",1,8,f);le32(f,16);
    le16(f,1);le16(f,1);le32(f,SAMPLE_RATE);
    le32(f,SAMPLE_RATE*2u);le16(f,2);le16(f,16);
    fwrite("data",1,4,f);le32(f,samples*2u);
    return ferror(f)?-1:0;
}
int main(int argc,char **argv) {
    if(argc!=2) {
        fprintf(stderr,"Usage: %s output.wav\n",argv[0]);return 2;
    }
    ssi263_params p;
    ssi263_default_params(&p);
    p.xck_hz=1020000.0f;
    ssi263 *chip=ssi263_new(&p,ssi263_default_rom(),(real)SAMPLE_RATE);
    if(!chip)return 3;
    FILE *f=fopen(argv[1],"wb+");
    if(!f){perror(argv[1]);ssi263_free(chip);return 4;}
    write_wav_header(f,0);
    ssi263_write(chip,3,0x80);
    ssi263_write(chip,0,0xC0);  /* latch mode 3 on power up */
    ssi263_write(chip,4,0xE8);
    ssi263_write(chip,2,0x48);
    ssi263_write(chip,1,0x1B); /* SHALL initial ~69Hz */
    ssi263_write(chip,3,0x69);

    uint32_t total=0,nonzero=0;
    uint32_t peak=0;
    real sample[CHUNK+1];
    short pcm[CHUNK+1];
    for(size_t i=0;i<sizeof(phrase);++i) {
        if(i==4) ssi263_write(chip,1,0x3B);  /* WE: ~80Hz */
        if(i==7) ssi263_write(chip,1,0x53);  /* PLAY and A: ~91Hz */
        if(i==12)ssi263_write(chip,1,0x83);  /* anticipate GAME pitch in gap, ~124Hz */
        if(i==14)ssi263_write(chip,1,0xAB);  /* final vowel->nasal glide, ~181Hz */
        ssi263_write(chip,0,phrase[i]);
        unsigned blocks=0;
        do {
            if(ssi263_run(chip,CHUNK,sample)!=CHUNK)goto fail;
            ssi_pcm16(sample,CHUNK,p.output_gain,pcm);
            for(int j=0;j<CHUNK;j++) {
                int32_t x=pcm[j];
                uint32_t ax=(uint32_t)(x<0?-x:x);
                if(ax>peak)peak=ax;
                if(x)nonzero++;
                le16(f,(uint16_t)pcm[j]);
            }
            total+=CHUNK;
            blocks++;
            if(blocks>512) {
                fprintf(stderr,"A/R timeout at phoneme %zu (%02X)\n",i,phrase[i]);
                goto fail;
            }
        } while(!ssi263_request(chip));
        if(i==3 || i==6 || i==10 || i==12 || i==14 || i==15) {
            real state[40];
            if(ssi263_state(chip,state,40)<14)goto fail;
            /* Exact glottal oscillator frequency from the real Pico model;
             * not a claim of actor pitch and not a host-side DSP effect. */
            double f0=(double)p.xck_hz/
                ((double)p.pitch_xck_div*(4096.0-2048.0-(double)state[2]));
            fprintf(stderr,"Take4 F0 i=%zu R1=%02X model=%.1fHz target=%.0f\n",
                    i,ssi263_reg(chip,1),f0,(double)state[3]);
            if((i==3 && (f0<65.0 || f0>77.0)) ||
               (i==6 && (f0<74.0 || f0>87.0)) ||
               (i==10 && (f0<86.0 || f0>96.0)) ||
               (i==15 && (f0<165.0 || f0>190.0)))goto fail;
        }
    }
    ssi263_write(chip,3,0x80);
    if(write_wav_header(f,total))goto fail;
    if(fclose(f))return 5;
    ssi263_free(chip);
    fprintf(stderr,"WOPR ROM=%zu phoneme records duration=%.3fs samples=%lu nonzero=%lu peak=%lu\n",
            sizeof(phrase),(double)total/SAMPLE_RATE,(unsigned long)total,
            (unsigned long)nonzero,(unsigned long)peak);
    return (nonzero && peak>100 && peak<32767 && total>SAMPLE_RATE && total<8*SAMPLE_RATE)?0:1;
fail:
    fclose(f);
    ssi263_free(chip);
    return 6;
}
