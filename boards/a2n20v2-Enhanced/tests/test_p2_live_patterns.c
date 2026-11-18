/* Original synthetic MOD direct-order runtime playback regression.
 * Test Bxx/Dxx/E6x at actual tick boundaries, not offline flattened.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sensei_mod_player.h"

static const uint8_t order_list[2]={0,1};
static uint8_t pattern_data[2*1024];
static uint8_t catalog[32*8];
static unsigned writes,starts,zero_vol;
static uint16_t previous_ms;

static void emit(uint16_t ms,uint8_t reg,uint8_t val)
{
    if(writes && (int16_t)(ms-previous_ms)<0) {
        fprintf(stderr,"P2 timestamps not increasing\n");
        exit(1);
    }
    previous_ms=ms;
    writes++;
    if(reg==0xA0 && !(val&1u))starts++;
    if(reg==0x40 && !val)zero_vol++;
}
static void fail(const char *message)
{
    fprintf(stderr,"FAIL P2 live patterns: %s\n",message);
    exit(1);
}
int main(void)
{
    sensei_mod_player_t p;
    /* instrument 1 starts in bank page 0 at volume 48 */
    catalog[11]=48;
    /* pattern 0, row 0, ch0, trigger instrument 1, period 428 */
    pattern_data[0]=0x01;pattern_data[1]=0xAC;pattern_data[2]=0x10;
    /* pattern 0 row 1: E60 defines loop start */
    pattern_data[16+2]=0x0E;pattern_data[16+3]=0x60;
    /* pattern 0 row 2: E61 repeat once */
    pattern_data[32+2]=0x0E;pattern_data[32+3]=0x61;
    /* pattern 0 row 3: D00 skips rest of pattern */
    pattern_data[48+2]=0x0D;pattern_data[48+3]=0;
    /* pattern 1 row 0: retrigger instrument */
    pattern_data[1024]=0x01;pattern_data[1025]=0xAC;
    pattern_data[1024+2]=0x10;
    /* pattern 1 row 1: tempo 150 */
    pattern_data[1024+16+2]=0x0F;
    pattern_data[1024+16+3]=150;
    /* pattern 1 row 2: jump beyond final order -> end */
    pattern_data[1024+32+2]=0x0B;
    pattern_data[1024+32+3]=2;

    if (!sensei_mod_init_runtime(&p,pattern_data,order_list,2,catalog,200))
        fail("initialization failed");
    for(unsigned t=0;t<100 && !sensei_mod_done(&p);t++)
        if(!sensei_mod_tick(&p,emit))fail("tick returned false");
    if(!sensei_mod_done(&p))fail("song flow did not finish");
    if(p.visited_rows!=9) {
        fprintf(stderr,"visited %lu rows\n",(unsigned long)p.visited_rows);
        fail("runtime D00/E61/B02 row traversal");
    }
    if(starts!=2 || writes<14 || p.bpm!=150 || p.order_pos!=2) {
        fprintf(stderr,"starts=%u writes=%u bpm=%u order=%u\n",
                starts,writes,p.bpm,p.order_pos);
        fail("events/retrigger/tempo/order state");
    }
    printf("PASS P2 raw MOD: %lu real-time rows, %u DOC writes, "
           "%u retriggers, 150 BPM and Bxx/Dxx/E6x flow\n",
           (unsigned long)p.visited_rows,writes,starts);
    return 0;
}
