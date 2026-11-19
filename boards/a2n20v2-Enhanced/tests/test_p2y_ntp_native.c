/*
 * P2Y: native NTP raw-pattern replayer; no MOD row encoding.
 * Synthesizes NTP score metadata only; real songs remain user-owned.
 * The companion HDL test checks the completion retarget in the FPGA.
 */
#include "sensei_ntp_native.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint16_t at; uint8_t reg,val; } event_t;
static event_t trace[2048];
static unsigned n;
static uint8_t patterns[2048],catalog[32u*8u],orders[2]={0,1};
static uint8_t pan[4]={0x10u,0u,0u,0x10u};
static uint8_t map[64],irq[32];
static sensei_ntp_player_t s;

static void require(int yes,const char *msg)
{
    if(!yes){fprintf(stderr,"FAIL P2Y NTP C: %s\n",msg);exit(1);}
}
static void emit(uint16_t at,uint8_t reg,uint8_t val)
{
    require(n<sizeof(trace)/sizeof(trace[0]),"event capture capacity");
    trace[n++]=(event_t){at,reg,val};
}
static int last(uint8_t reg)
{
    for(unsigned i=n;i;i--)
        if(trace[i-1].reg==reg)return trace[i-1].val;
    return -1;
}
static unsigned seen(uint8_t reg,uint8_t val)
{
    unsigned hits=0;
    for(unsigned i=0;i<n;i++)
        if(trace[i].reg==reg && trace[i].val==val)hits++;
    return hits;
}
static void row(unsigned pat,unsigned line,unsigned ch,
                uint8_t note,uint8_t inst,uint8_t fx,uint8_t arg)
{
    unsigned off=pat*1024u+line*16u+ch*4u;
    patterns[off]=note;patterns[off+1]=inst;
    patterns[off+2]=fx;patterns[off+3]=arg;
}
static void fixture(void)
{
    memset(patterns,0,sizeof patterns);
    memset(catalog,0,sizeof catalog);
    memset(irq,0,sizeof irq);memset(map,0,sizeof map);
    map[1]=1;map[2]=2;
    catalog[8]=0;catalog[9]=0;catalog[10]=6;catalog[11]=48;
    catalog[12]=2;catalog[13]=9;catalog[14]=6;catalog[15]=1;
    irq[1]=1; /* Nonideal type 2 header + type 3 sustain. */
    catalog[16]=7;catalog[17]=0;catalog[18]=2;catalog[19]=64;
    /* NTP channel output 1 maps to physical LEFT, output 0 to RIGHT.
     * 0x10 in DOC CTRL selects left. Song data is NOT MOD L/R/L/R. */
    row(0,0,0,25,1,0,0x37);   /* split-loop head; arpeggio */
    row(0,0,1,25,2,0,0);      /* one-shot right */
    row(0,1,0,0,0,0,0);       /* arpeggio must release */
    row(0,2,0,0,1,0,0);       /* original NTP: sample with no note repeats */
    row(0,3,0,25,1,14,0x93); /* E93 note retrigger */
    row(0,4,0,25,1,14,0xC2); /* EC2 cut */
    row(0,5,0,25,1,14,0xD2); /* ED2 delayed note */
    row(0,6,0,0,0,15,0x40);  /* F40: 64 BPM */
    row(0,7,0,0,0,13,0x03);  /* D03: break to next order row 3 */
    row(1,3,0,25,2,15,0);    /* F00 stop */
}
static void tick(unsigned times)
{
    while(times--)require(sensei_ntp_tick(&s,emit),"unexpected end");
}
int main(void)
{
    fixture();
    require(sensei_ntp_init(&s,patterns,2,orders,2,catalog,pan,map,irq,100),
            "init raw NTP score");
    require(sensei_ntp_next_ms(&s)==200u,"start time");
    tick(1); /* row0 tick0 */
    require(s.note_starts[0]==1 && s.note_starts[1]==1,
            "both NTP raw instrument records started");
    require(last(0xA0)==0x1Eu && last(0xA1)==0x17u,
            "native left split-loop must request 0x0E IRQ|SWAP");
    require(last(0xA2)==0x02u && last(0xA3)==0x01u,
            "one-shot right control/partner HALT");
    require(last(0x40)==192 && last(0x42)==255,
            "original NTP volume is 4x, not P2U 3x");
    require(last(0x80)==0 && last(0x81)==2 &&
            last(0xC1)==9,"original DOC head/sustain pointers copied");
    require(s.tick==1u && s.order_pos==0u && s.row==0u,
            "NTP begins at pattern zero");
    printf("PASS P2Y: native NTP note, stereo, volume, FPGA retarget signature\n");
    tick(5); /* arpeggio */
    require(s.row==1u && s.tick==0u,"NTP row tick transition");
    n=0;tick(1); /* row1 blank, pitch releases */
    require(last(0)==161 && last(1)==161,
            "arpeggio root restores on both DOC oscillators");
    tick(5);
    n=0;tick(1); /* row2: instrument without note */
    require(s.note_starts[0]==2u &&
            seen(0xA0,0x1Eu)==1u,
            "NTP instrument-only row must repeat previous note");
    printf("PASS P2Y: raw-score instrument-only retrigger and pitch release\n");
    tick(5);
    n=0;tick(1); /* row3 E93 */
    unsigned before=s.note_starts[0];
    tick(3);
    require(s.note_starts[0]==before+1u,
            "E93 retriggers on tick 3");
    tick(2);
    tick(1); /* row4 EC2 */
    tick(2);
    require(s.ch[0].volume==0u && last(0x40)==0u,
            "EC2 note cut on tick 2");
    tick(3);
    n=0;tick(1); /* row5 ED2 */
    unsigned delayed=s.note_starts[0];
    tick(1);
    require(delayed==s.note_starts[0],"ED2 must defer note at tick1");
    tick(1);
    require(s.note_starts[0]==delayed+1u,"ED2 fires note on tick2");
    tick(3);
    tick(1); /* row6 F40 */
    require(s.bpm==64u,"NTP F40 changes tempo");
    tick(5);
    tick(6); /* row7 D03 */
    require(s.order_pos==1u && s.row==3u,
            "D03 must break to row 3 in next order");
    tick(1); /* F00 */
    require(sensei_ntp_done(&s),"NTP F00 stops without hanging");
    printf("PASS P2Y: E9, EC, ED, Fxx, Dxx control and song completion\n");

    /* Original NTP's single pattern-loop cursor is used in Dead Waltz.
     * E60 marks the start; E61 returns once, then progresses to row 2. */
    memset(patterns,0,sizeof patterns);
    row(0,0,0,0,0,14,0x60u);
    row(0,1,0,0,0,14,0x61u);
    row(0,2,0,0,0,15,0x00u);
    require(sensei_ntp_init(&s,patterns,1,orders,1,catalog,pan,map,irq,100),
            "init Dead Waltz E6 loop score");
    tick(6);require(s.row==1u,"E60 set loop start");
    tick(6);require(s.row==0u,"E61 repeat once");
    tick(6);require(s.row==1u,"E60 loop restart");
    tick(6);require(s.row==2u,"E61 completion must advance");
    tick(1);require(sensei_ntp_done(&s),"F00 after finite E6 loop");
    printf("PASS P2Y: native NTP E60/E61 finite pattern loop and song stop\n");
    return 0;
}
