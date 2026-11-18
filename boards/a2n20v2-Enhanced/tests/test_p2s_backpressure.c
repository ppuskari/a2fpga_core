/*
 * P2S real BL616 MOD interpreter -> staged DOC event queue -> mocked
 * 64-entry FPGA FIFO with consume/backpressure.
 * Specifically reproduces the old P2R failure: 24 events already
 * queued + 56 events from 4 simultaneous attack/sustain notes.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sensei_mod_player.h"
#include "sensei_event_queue.h"

static sensei_event_queue_t stage;
static sensei_event_t fpga[64],accepted[1024],generated[1024];
static unsigned fpga_count, accepted_count, generated_count, drop_count;
static void fail(const char *why)
{
    fprintf(stderr,"P2S FAIL: %s\n",why);
    exit(1);
}
static void gen(uint16_t t,uint8_t r,uint8_t d)
{
    if(generated_count>=1024)fail("fixture exceeds reference capacity");
    generated[generated_count++]=(sensei_event_t){t,r,d};
    if(!sensei_queue_push(&stage,t,r,d))fail("MCU staging overflow");
}
static void deliver(uint16_t t,uint8_t r,uint8_t d)
{
    if(fpga_count>=64) {drop_count++;return;}
    fpga[fpga_count++]=(sensei_event_t){t,r,d};
    if(accepted_count>=1024)fail("accepted trace overflow");
    accepted[accepted_count++]=(sensei_event_t){t,r,d};
}
static void consume(unsigned n)
{
    if(n>fpga_count)n=fpga_count;
    memmove(fpga,fpga+n,(fpga_count-n)*sizeof fpga[0]);
    fpga_count-=n;
}
static void assert_trace(void)
{
    if(accepted_count!=generated_count)
        fail("events delivered count mismatch");
    for(unsigned i=0;i<accepted_count;i++) {
        if(memcmp(&accepted[i],&generated[i],sizeof accepted[i])!=0)
            fail("event timestamp/data/order changed");
    }
}
static void four_attack_notes(void)
{
    sensei_mod_player_t mod;
    uint8_t patterns[1024]={0},orders[1]={0},catalog[256]={0};
    // One row: 4 distinct notes with paired attack/sustain enabled.
    for(unsigned ch=0;ch<4;ch++) {
        unsigned inst=ch+1u;
        patterns[ch*4+0]=(uint8_t)(0x01u);
        patterns[ch*4+1]=0xAC;
        patterns[ch*4+2]=(uint8_t)(inst<<4);
        catalog[inst*8+0]=(uint8_t)(ch*8u);
        catalog[inst*8+1]=0x12;
        catalog[inst*8+2]=6; // MODE_SWAP, partner MODE_FREE
        catalog[inst*8+3]=48;
        catalog[inst*8+4]=(uint8_t)(ch*8u+4u);
        catalog[inst*8+5]=0;
        catalog[inst*8+6]=0;
        catalog[inst*8+7]=1;
    }
    if(!sensei_mod_init_runtime(&mod,patterns,orders,1,catalog,100))
        fail("runtime MOD init failed");
    if(!sensei_mod_tick(&mod,gen))fail("first row failed");
    if(generated_count<52 || generated_count>64)
        fail("expected a large four-channel attack burst");
}
int main(void)
{
    sensei_queue_reset(&stage);
    // Model 24 older events physically in the FPGA FIFO; original P2R
    // submitted another >40 without an occupancy check and dropped ~16.
    fpga_count=24;
    four_attack_notes();
    unsigned n=sensei_queue_drain(&stage,24,64,100,64,deliver);
    if(n!=40 || stage.count!=generated_count-40 ||
       fpga_count!=64 || drop_count)fail("bad first backpressure pass");
    if(sensei_queue_drain(&stage,64,64,100,64,deliver)!=0)
        fail("wrote to full FPGA FIFO");
    // Synthetic physical DOC playback frees 24 slots.
    consume(24);
    n=sensei_queue_drain(&stage,40,64,101,64,deliver);
    if(n!=generated_count-40 || stage.count || drop_count)
        fail("did not resume after FPGA consumption");
    assert_trace();
    if(stage.accepted!=stage.emitted || stage.failed || stage.high_water<52)
        fail("lost/duplicated generated events");
    puts("PASS P2S: 24 prior events + four simultaneous DOC pairs, zero drops");
    puts("PASS P2S: all timestamps, DOC register values and original order preserved");

    // Simulate on-the-fly retriggers while the 64-entry FPGA queue
    // remains backpressured, then rapid STOP clearing pending MCU work.
    sensei_queue_reset(&stage);
    generated_count=accepted_count=fpga_count=drop_count=0;
    for(unsigned i=0;i<200;i++)
        gen((uint16_t)(100u+i/10u),(uint8_t)(0xA0u+(i%8u)),
            (uint8_t)i);
    if(sensei_queue_drain(&stage,64,64,100,64,deliver)!=0 ||
       stage.count!=200u)fail("full hardware FIFO must defer queued retriggers");
    for(unsigned cycle=0;stage.count && cycle<20;cycle++) {
        unsigned len=sensei_queue_drain(&stage,fpga_count,64,
                                        (uint16_t)(101u+cycle),16,deliver);
        if(len>16 || fpga_count>64 || drop_count)fail("bounded pump overflow");
        consume(16);
    }
    if(stage.count || stage.emitted!=200u)
        fail("stress backlog failed to drain");
    assert_trace();
    puts("PASS P2S: 200 retrigger/control writes drained with bounded backpressure");

    sensei_queue_reset(&stage);
    generated_count=accepted_count=fpga_count=drop_count=0;
    for(unsigned ch=0;ch<8;ch++) {
        gen(500,(uint8_t)(0x40u+ch),0);
        gen(500,(uint8_t)(0xA0u+ch),1);
    }
    if(sensei_queue_drain(&stage,0,64,501,64,deliver)!=16 ||
       stage.count || drop_count || stage.late!=16 || stage.max_late_ms!=1)
        fail("STOP mutes/late accounting incorrect");
    assert_trace();
    puts("PASS P2S: eight DOC oscillators STOP without discarded events");
    return 0;
}
