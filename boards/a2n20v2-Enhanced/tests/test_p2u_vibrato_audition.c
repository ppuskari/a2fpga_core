/* P2U: direct ProTracker runtime regression against 15k-style CH2 vibrato
 * and HDMI console channel audition. Uses the production player and
 * synthetic wave/catalog data, NOT private MOD song/sample assets.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sensei_mod_player.h"

struct event {uint16_t time;uint8_t reg,data;};
static struct event got[128];
static unsigned count;
static uint8_t pattern[1024],catalog[32*8];
static const uint8_t orders[1]={0};
static void check(int ok,const char *why)
{
    if(!ok){fprintf(stderr,"FAIL P2U: %s\n",why);exit(1);}
}
static void event(uint16_t when,uint8_t reg,uint8_t data)
{
    check(count<128u,"out of event buffer");
    got[count++]=(struct event){when,reg,data};
}
static void note(unsigned channel,unsigned period,unsigned fx,unsigned arg)
{
    uint8_t *p=pattern+channel*4u;
    p[0]=(uint8_t)((period>>8)&15u);
    p[1]=(uint8_t)period;
    p[2]=(uint8_t)(0x10u | fx); /* instrument 1 */
    p[3]=(uint8_t)arg;
}
static int get_last(uint8_t addr)
{
    for(unsigned i=count;i;i--)
        if(got[i-1u].reg==addr)return got[i-1u].data;
    return -1;
}
static void check_only_right_two(void)
{
    for(unsigned i=0;i<count;i++) {
        const uint8_t reg=got[i].reg,bank=(uint8_t)(reg&0xE0u);
        if(bank==0x00u||bank==0x20u||bank==0x40u||
           bank==0x80u||bank==0xA0u||bank==0xC0u)
            check((reg&31u)==4u || (reg&31u)==5u,
                  "non-selected channel emitted DOC register");
    }
}
int main(void)
{
    sensei_mod_player_t s;
    catalog[8+2]=6u;  /* attack MODE_SWAP */
    catalog[8+3]=48u;
    catalog[8+4]=4u;  /* sustain */
    catalog[8+7]=1u;
    for(unsigned ch=0;ch<4;ch++)
        note(ch,428,ch==2?4u:0u,ch==2?0x47u:0u);
    check(sensei_mod_init_runtime(&s,pattern,orders,1,catalog,100),
          "init");
    check(s.audition_mask==15u,"default audition must play all channels");
    s.audition_mask=4u; /* CH2 right only */
    check(sensei_mod_tick(&s,event),"tick0");
    check(count==14u,"solo must emit exactly one paired note start");
    check_only_right_two();
    check(get_last(0xA4)==6 && get_last(0xA5)==1,
          "incorrect right channel controls");
    for(unsigned ch=0;ch<4;ch++)
        check(s.note_starts[ch]==1u,"muted channels must still advance notes");
    puts("PASS P2U: CH2 solo emits only DOC4/5, tracks all four MOD channels");

    count=0;
    check(sensei_mod_tick(&s,event),"vibrato tick1");
    check(count==4u && get_last(4)==161 && get_last(5)==161,
          "vibrato tick1 base period");
    count=0;
    check(sensei_mod_tick(&s,event),"vibrato tick2");
    check(count==4u && get_last(4)==156 && get_last(5)==156,
          "vibrato at phase16 must be >2x P2T depth");
    count=0;
    check(sensei_mod_tick(&s,event),"vibrato tick3");
    check(count==4u && get_last(4)==161 && get_last(5)==161,
          "vibrato phase32 must return to root");
    count=0;
    check(sensei_mod_tick(&s,event),"vibrato tick4");
    check(count==4u && get_last(4)==167 && get_last(5)==167,
          "vibrato phase48 negative swing");
    count=0;
    check(sensei_mod_tick(&s,event),"vibrato tick5");
    check(count==4u,"vibrato fifth tick");
    count=0;
    check(sensei_mod_tick(&s,event),"blank row tick0");
    check(count==4u && get_last(4)==161 && get_last(5)==161,
          "restore root frequency on following row");
    check_only_right_two();
    puts("PASS P2U: PT2 vibrato speed*4, period depth/128, row-base restore");

    /* Test RIGHT pair audition without modifying global pattern flow. */
    check(sensei_mod_init_runtime(&s,pattern,orders,1,catalog,100),
          "right pair init");
    s.audition_mask=6u;
    count=0;
    check(sensei_mod_tick(&s,event),"right pair tick0");
    check(count==28u,"right pair should emit two starts, not four");
    for(unsigned i=0;i<count;i++) {
        const unsigned voice=(unsigned)(got[i].reg&31u);
        check(voice>=2u && voice<=5u,"right pair leaked left output");
    }
    puts("PASS P2U: right-pair audition CH1+CH2, no left-note leakage");
    return 0;
}
