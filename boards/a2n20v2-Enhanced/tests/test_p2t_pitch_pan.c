/* P2T: ProTracker stereo and row-boundary pitch restoration regression.
 * Real sensei_mod_player.c, no precomputed song traces or copyrighted PCM.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sensei_mod_player.h"
typedef struct { uint16_t at; uint8_t reg,value; } evt_t;
static evt_t logbuf[512];
static unsigned n;
static uint8_t patterns[1024],catalog[32*8],order[1]={0};
static void check(int ok,const char*msg)
{
    if(!ok){fprintf(stderr,"FAIL P2T: %s\n",msg);exit(1);}
}
static void emit(uint16_t at,uint8_t reg,uint8_t value)
{
    if(n==512u)check(0,"log capacity");
    logbuf[n++]=(evt_t){at,reg,value};
}
static void put_note(unsigned ch,unsigned period,unsigned instrument,
                     unsigned fx,unsigned param)
{
    unsigned off=ch*4u;
    patterns[off]=(uint8_t)((instrument&0xF0u)|((period>>8)&15u));
    patterns[off+1]=(uint8_t)period;
    patterns[off+2]=(uint8_t)(((instrument&15u)<<4)|(fx&15u));
    patterns[off+3]=(uint8_t)param;
}
static unsigned count_reg_val(uint8_t reg,uint8_t value)
{
    unsigned hits=0;
    for(unsigned i=0;i<n;i++)
        if(logbuf[i].reg==reg && logbuf[i].value==value)hits++;
    return hits;
}
static int last(uint8_t reg)
{
    for(unsigned i=n;i;i--)
        if(logbuf[i-1u].reg==reg)return logbuf[i-1u].value;
    return -1;
}
int main(void)
{
    sensei_mod_player_t p;
    catalog[8+2]=6;catalog[8+3]=48;catalog[8+7]=1;
    // ProTracker channel 0 and 3 are LEFT, 1 and 2 RIGHT.
    put_note(0,428,1,0,0x37); // repeating 0xy arpeggio
    put_note(1,428,1,4,0x47); // vibrato
    put_note(2,428,1,0,0);
    put_note(3,428,1,0,0);
    check(sensei_mod_init_runtime(&p,patterns,order,1,catalog,100),
          "init runtime");
    check(sensei_mod_tick(&p,emit),"tick zero");
    check(n==56u,"four paired-oscillator note starts should emit 56 writes");
    for(unsigned ch=0;ch<4;ch++) {
        const uint8_t pan=(ch==0u || ch==3u)?0x10u:0u;
        const uint8_t first=(uint8_t)(2u*ch);
        check(last((uint8_t)(0xA0u+first))==(int)(pan|6u),
              "attack control incorrectly panned");
        check(last((uint8_t)(0xA1u+first))==(int)(pan|1u),
              "sustain partner incorrectly panned");
    }
    puts("PASS P2T: DOC control uses true ProTracker L/R/R/L assignment");
    for(unsigned i=1;i<6;i++)
        check(sensei_mod_tick(&p,emit),"row zero subsequent tick");
    // Tracker's last arpeggio tick is non-root pitch, and vibrato moves
    // away from the base. Tick 0 of a blank next row must reset FC.
    check(last(0)!=161,"test fixture arpeggio was not detuned by tick5");
    n=0;
    check(sensei_mod_tick(&p,emit),"blank next row tick zero");
    check(n==8u,"base pitch should restore on BOTH paired DOC oscillators");
    check(last(0)==161 && last(1)==161 && last(2)==161 && last(3)==161,
          "incorrect restored FC low byte");
    check(last(0x20)==0 && last(0x21)==0 &&
          last(0x22)==0 && last(0x23)==0,
          "incorrect restored FC high byte");
    check(!count_reg_val(0xA0,0x16) && !count_reg_val(0xA2,0x06),
          "row boundary spuriously restarted notes");
    puts("PASS P2T: arpeggio and vibrato restore base FC at next row tick0");
    n=0;
    for(unsigned i=1;i<6;i++)
        check(sensei_mod_tick(&p,emit),"blank row nonzero tick");
    check(n==0u,"blank row should not generate spurious events");
    puts("PASS P2T: empty rows leave stable base pitch");
    return 0;
}
