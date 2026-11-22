/* J2R10: real osd_console.c under the host fake-HID and FPGA SPI backend.
 * Assert no OSD writes occur on osd_log() even if console is visible;
 * one refresh coalesces many lines after 1s. Apple video and lockout
 * semantics, immediate show(), and telnet tee remain unchanged.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "usb_osal.h"
#include "fpga_spi.h"
#include "fpga_screen.h"
#include "bflb_mtimer.h"
#include "osd_console.h"

#define CHECK(p) do { if(!(p)) { \
  fprintf(stderr,"FAIL J2R10 OSD at line %d: %s\n",__LINE__,#p);exit(1); \
} } while(0)

static uint64_t s_now;
static unsigned s_clear,s_puts,s_reg,s_tee,s_take,s_give;
static uint8_t s_video;
static char s_last_line[41];

usb_osal_mutex_t usb_osal_mutex_create(void) { return (void*)1; }
void usb_osal_mutex_take(usb_osal_mutex_t m) { CHECK(m==(void*)1); ++s_take; }
void usb_osal_mutex_give(usb_osal_mutex_t m) { CHECK(m==(void*)1); ++s_give; }
uint64_t bflb_mtimer_get_time_us(void) { return s_now; }
void fpga_spi_reg_write(uint8_t reg,uint8_t value)
{
    CHECK(reg==0x10 || reg==0x11);
    ++s_reg;
    if(reg==0x10)s_video=value;
}
void fpga_screen_clear(void) { ++s_clear; }
void fpga_screen_home(void) {}
void fpga_screen_puts(const char *s) { (void)s; ++s_puts; }
void telnetd_console_tee(const char *s)
{
    ++s_tee;
    snprintf(s_last_line,sizeof s_last_line,"%s",s);
}
int main(void)
{
    osd_log("BOOT %u",1u);
    CHECK(s_clear==0 && s_reg==0 && s_tee==1);
    osd_console_service();
    CHECK(s_clear==0); /* hidden: no writes, no repaint */
    osd_console_show();
    CHECK(s_clear==1 && s_reg==2 && s_video==1);
    s_now=100000u;
    for(unsigned i=0;i<32;i++)osd_log("MOD SAMPLE %u",i);
    CHECK(s_clear==1 && s_reg==2 && s_tee==33);
    osd_console_service();
    CHECK(s_clear==1);
    s_now=999999u;
    osd_console_service();
    CHECK(s_clear==1);
    s_now=1000001u;
    osd_console_service();
    CHECK(s_clear==2 && s_reg==2);
    osd_console_service();
    CHECK(s_clear==2); /* no changes, no write */
    s_now=2000001u;
    osd_console_service();
    CHECK(s_clear==2); /* stale (no dirty lines) */
    char rows[23][41];
    int count=osd_console_snapshot(rows,23);
    CHECK(count==23);
    CHECK(strstr(rows[22],"MOD SAMPLE 31")!=NULL);
    osd_console_set_lockout(true);
    osd_log("LOCKED COUNTER");
    s_now=5000000u;
    osd_console_service();
    CHECK(s_clear==2);
    osd_console_show();
    CHECK(s_clear==2);
    osd_console_set_lockout(false);
    osd_console_show(); /* explicit user request => immediate refresh */
    CHECK(s_clear==3 && s_video==1);
    osd_console_hide();
    CHECK(s_video==0);
    osd_log("HIDDEN");
    s_now=9000000u;
    osd_console_service();
    CHECK(s_clear==3);
    CHECK(s_take==s_give);
    CHECK(!strcmp(s_last_line,"HIDDEN"));
    printf("PASS J2R10: 34+ console lines, 3 deliberate FPGA frames, "
           "no producer redraw, menu lockout/hidden/telnet intact\n");
    return 0;
}
