/* Native GCC integration test of the actual P1E MCU MOD tick interpreter.
 * Uses an original synthetic 4-channel fixture, not any user-owned MOD.
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "sensei_mod_player.h"

static uint32_t writes,frequency_writes,volume_writes,note_starts,stops;
static uint16_t previous_when;
static void doc_emit(uint16_t when,uint8_t address,uint8_t data)
{
    if (writes && (int16_t)(when-previous_when)<0) {
        fprintf(stderr,"P1E event time went backwards\n");
        exit(1);
    }
    previous_when=when;
    ++writes;
    if (address<4 || (address>=0x20 && address<0x24)) ++frequency_writes;
    if (address>=0x40 && address<0x44) {
        ++volume_writes;
        if (data==0) ++stops;
    }
    if (address>=0xA0 && address<0xA4 && !(data&1)) ++note_starts;
}
static void run_song(uint8_t song)
{
    sensei_mod_player_t state;
    uint16_t start,ending;
    unsigned guard=0;
    writes=frequency_writes=volume_writes=note_starts=stops=0;
    previous_when=0;
    if (!sensei_mod_init(&state,song,1000))
        {fprintf(stderr,"P1E missing synthetic fixture\n");exit(1);}
    start=sensei_mod_next_ms(&state);
    while(!sensei_mod_done(&state) && ++guard<100) {
        if (!sensei_mod_tick(&state,doc_emit))
            {fprintf(stderr,"P1E tick unexpectedly failed\n");exit(1);}
    }
    ending=sensei_mod_next_ms(&state);
    if (!sensei_mod_done(&state) || guard<15 || guard>40 ||
        writes<35 || frequency_writes<10 || volume_writes<5 ||
        note_starts<3 || stops<1 || ending<=start) {
        fprintf(stderr,"P1E song%u failed ticks=%u events=%lu freq=%lu vol=%lu "
                       "starts=%lu stops=%lu start=%u end=%u\n",
                song,guard,(unsigned long)writes,
                (unsigned long)frequency_writes,(unsigned long)volume_writes,
                (unsigned long)note_starts,(unsigned long)stops,start,ending);
        exit(1);
    }
    printf("PASS P1E ID%u: %u tracker ticks; %lu DOC events; %lu pitch; "
           "%lu volume; %lu note runs; %lu cuts\n",song,guard,
           (unsigned long)writes,(unsigned long)frequency_writes,
           (unsigned long)volume_writes,(unsigned long)note_starts,
           (unsigned long)stops);
}
int main(void)
{
    if (!sensei_mod_available()) return 1;
    run_song(1);
    run_song(2);
    return 0;
}
