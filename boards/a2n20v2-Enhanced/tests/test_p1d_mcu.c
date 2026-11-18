/* Host-side functional simulation of Sensei P1D BL616 tracker task.
 * Exercises a full 192-row demo plus a mid-song STOP handshake.
 * Not a substitute for Bouffalo SDK linking / physical timing.
 */
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <setjmp.h>
#include "FreeRTOS.h"
#include "task.h"
#include "fpga_spi.h"
#include "osd_console.h"

/* Compile actual firmware source into this translation unit, never a
 * separately rewritten model of tracker state transitions. */
#include "../src/a2n20_bl616/firmware_host/sensei_tracker.c"

static jmp_buf test_return;
static uint32_t fake_ms, events;
static uint8_t owner, playback, command, sequence, argument;
static bool stop_test;

static void fail(const char *why) {
    fprintf(stderr,"P1D MCU FAIL: %s at fake_ms=%lu events=%lu\n",
            why,(unsigned long)fake_ms,(unsigned long)events);
    exit(1);
}
void osd_log(const char *fmt, ...) {(void)fmt;}

void fpga_spi_xfer_read(uint8_t space, uint32_t addr, uint8_t *dst, uint16_t n)
{
    if (space != 6 || addr != 0 || n != 13)
        fail("Unexpected SPI status read");
    memset(dst,0,n);
    dst[0]=0x53;dst[1]=0x1D;
    dst[2]=command;dst[3]=sequence;dst[4]=argument;
    dst[5]=playback;dst[6]=0; /* FIFO consumption under hardware test */
    dst[8]=(uint8_t)fake_ms;
    dst[9]=(uint8_t)(fake_ms>>8);
    dst[12]=1u+(owner?2u:0u);
}

void fpga_spi_xfer_write(uint8_t space, uint32_t addr,
                         const uint8_t *buf, uint16_t len)
{
    if (space!=6)fail("wrong SPI space");
    if (addr==0x10) {
        if (len!=5 || buf[4]!=0xA5 || !owner)
            fail("malformed/ownerless timed DOC event");
        events++;
    } else if (addr==0x16) {
        if (len!=1 || buf[0]>1)fail("bad owner control");
        owner=buf[0];
    } else if (addr==0x15) {
        if (len!=1 || buf[0]!=0xA5)fail("bad queue flush");
    } else if (addr==0x05) {
        if (len!=1)fail("bad state update");
        playback=buf[0];
    } else {
        fail("unknown SPI write");
    }
}
void vTaskDelay(uint32_t ticks)
{
    fake_ms+=ticks ? ticks : 1;
    if (stop_test && fake_ms>650 && sequence==1) {
        sequence=2;
        command=2;
    }
    if (stop_test && playback==STATE_IDLE && fake_ms>650 && !owner)
        longjmp(test_return,1);
    if (!stop_test && playback==STATE_DONE && !owner)
        longjmp(test_return,1);
    if (fake_ms>26000)
        fail("MCU did not complete by 26 seconds");
}

static void run_test(bool stop)
{
    fake_ms=0;events=0;owner=0;playback=0;
    command=1;sequence=1;argument=0;stop_test=stop;
    if (!setjmp(test_return)) {
        sensei_tracker_task(NULL);
        fail("infinite worker unexpectedly returned");
    }
    if (owner)fail("DOC ownership leaked");
    if (stop) {
        if (playback!=STATE_IDLE || fake_ms<650 || events<40 || events>2000)
            fail("STOP handshake incorrect");
        printf("PASS P1D MCU STOP: %lu events, release at %lu ms\n",
               (unsigned long)events,(unsigned long)fake_ms);
    } else {
        if (playback!=STATE_DONE || fake_ms<23000 || fake_ms>24000 ||
            events<5000 || events>7000)
            fail("192-row complete playback incorrect");
        printf("PASS P1D MCU DONE: %lu events, finish at %lu ms\n",
               (unsigned long)events,(unsigned long)fake_ms);
    }
}

int main(void)
{
    if (period_to_fc(428)!=161)fail("DOC pitch not compatible with P0");
    run_test(false);
    run_test(true);
    return 0;
}
