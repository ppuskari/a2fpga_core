/* R11 / WarGames: prove R1 pitch writes actually change the native Pico
 * SSI-263 state and realized glottal oscillator, not just demo metadata.
 * From the actual Take3 R0 score and R1 sequence. */
#include <stdio.h>
#include <stdint.h>
#include "ssi263.h"
#define N 64
static const unsigned char phrase[]={
    0x72,0x0C,0x20,0xC0,
    0xA3,0x01,0x80,
    0xE7,0xA0,0x05,0xC0,
    0x0E,0xC0,
    0x66,0x05,0x77,0x80
};
int main(void) {
    ssi263_params p; ssi263_default_params(&p);
    p.xck_hz=1020000.0f;
    ssi263 *c=ssi263_new(&p,ssi263_default_rom(),22050.0f);
    if(!c)return 2;
    ssi263_write(c,3,0x80);ssi263_write(c,0,0xC0);
    ssi263_write(c,4,0xE8);ssi263_write(c,2,0x48);
    ssi263_write(c,1,0x33);ssi263_write(c,3,0x69);
    real out[N+1],state[40];
    printf("PITCH: mode at start=%d reg1=%02X\n",ssi263_mode(c),ssi263_reg(c,1));
    for(unsigned i=0;i<sizeof phrase;i++) {
        if(i==4)ssi263_write(c,1,0x43);
        if(i==7)ssi263_write(c,1,0x53);
        if(i==12)ssi263_write(c,1,0x83);
        ssi263_write(c,0,phrase[i]);
        int count=0;
        do {
            if(ssi263_run(c,N,out)!=N)return 3;
            if(++count>512)return 4;
        }while(!ssi263_request(c));
        ssi263_state(c,state,40);
        double f0=p.xck_hz/(p.pitch_xck_div*(4096.0-2048.0-state[2]));
        printf("i=%u R0=%02X R1=%02X MODE=%.0f trans=%.1f target=%.1f hz=%.2f dur=%d\n",
               i,phrase[i],ssi263_reg(c,1),(double)state[13],
               (double)state[2],(double)state[3],f0,count);
    }
    ssi263_free(c);return 0;
}
