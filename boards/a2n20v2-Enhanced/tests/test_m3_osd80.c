/*
 * M3 post-release advanced console: exercise the real MCU fpga_screen.c and
 * osd_console.c against a byte-accurate 2-KiB OSD SDRAM mock.
 *
 * Key invariant: 40 columns = 40 screen codes at even byte addresses with
 * 0xA0 padding; 80 columns = all 80 byte lanes containing screen codes.
 * The 80-col path must always issue aligned complete 32-bit SPI writes.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "fpga_spi.h"
#include "fpga_screen.h"
#include "osd_console.h"
#include "usb_osal.h"

#define OSD_BASE 0x020800u
#define OSD_BYTES 2048u
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr,"FAIL M3 OSD80:%d: %s\n",__LINE__,#x); exit(1); \
} } while(0)

static uint8_t s_osd[OSD_BYTES];
static uint8_t s_regs[128];
static uint64_t s_now;
static unsigned s_writes,s_fills,s_reg_writes,s_tee,s_mutex_take,s_mutex_give;
static char s_last_tee[OSD_CONSOLE_LINE_CAP];

static uint32_t addr_of(unsigned x,unsigned y,unsigned width)
{
    return (0x50u * (y >> 3)) + ((y & 7u) << 8) +
           (width==40u ? 2u*x : x);
}
static unsigned osd_offset(uint32_t addr,unsigned count)
{
    CHECK(addr>=OSD_BASE && addr+count<=OSD_BASE+OSD_BYTES);
    return (unsigned)(addr-OSD_BASE);
}

void fpga_spi_reg_write(uint8_t reg,uint8_t value)
{
    CHECK(reg==0x10u || reg==0x11u || reg==0x17u);
    s_regs[reg]=value;
    ++s_reg_writes;
}
void fpga_spi_xfer_write(uint8_t space,uint32_t addr,
                         const uint8_t *src,uint16_t len)
{
    CHECK(space==FPGA_SPACE_SDRAM && src && len>0);
    if(fpga_screen_columns()==FPGA_SCREEN_WIDE_W) {
        CHECK((addr & 3u)==0u);
        CHECK((len & 3u)==0u);
    }
    memcpy(s_osd+osd_offset(addr,len),src,len);
    ++s_writes;
}
void fpga_spi_xfer_fill(uint8_t space,uint32_t addr,
                        uint8_t value,uint16_t len)
{
    CHECK(space==FPGA_SPACE_SDRAM && len==OSD_BYTES);
    memset(s_osd+osd_offset(addr,len),value,len);
    ++s_fills;
}
uint64_t bflb_mtimer_get_time_us(void) {return s_now;}
usb_osal_mutex_t usb_osal_mutex_create(void) {return (void *)1;}
void usb_osal_mutex_take(usb_osal_mutex_t m) {CHECK(m==(void *)1);s_mutex_take++;}
void usb_osal_mutex_give(usb_osal_mutex_t m) {CHECK(m==(void *)1);s_mutex_give++;}
void telnetd_console_tee(const char *line)
{
    CHECK(line);
    CHECK(strlen(line)<sizeof(s_last_tee));
    memcpy(s_last_tee,line,strlen(line)+1u);
    s_tee++;
}

int main(void)
{
    /* Original menus: 40 chars, interleaved padding, 2 KiB text page. */
    CHECK(fpga_screen_columns()==40u);
    fpga_screen_clear();
    fpga_screen_puts("ABCD");
    for(unsigned i=0;i<4u;i++) {
        CHECK(s_osd[addr_of(i,0u,40u)]==(uint8_t)('A'+i+128u));
        CHECK(s_osd[addr_of(i,0u,40u)+1u]==0xA0u);
    }
    fpga_screen_putchar('Z');
    CHECK(s_osd[addr_of(4u,0u,40u)]==(uint8_t)('Z'+128u));

    /* Switch to 80: every byte stores one code, no silent 40-col padding. */
    fpga_screen_set_columns(FPGA_SCREEN_WIDE_W);
    CHECK(fpga_screen_columns()==80u);
    fpga_screen_clear();
    char msg[80];
    for(unsigned i=0;i<79u;i++)msg[i]=(char)('A'+(i%26u));
    msg[79]=0;
    fpga_screen_puts(msg);
    for(unsigned i=0;i<79u;i++)
        CHECK(s_osd[addr_of(i,0u,80u)]==(uint8_t)(msg[i]+128u));
    CHECK(s_osd[addr_of(79u,0u,80u)]==0xA0u);
    CHECK(fpga_screen_shadow_row(0)[78]==(uint8_t)(msg[78]+128u));
    /* Single-character write must merge its neighbors into a full word. */
    uint8_t originalLeft=s_osd[addr_of(72u,0u,80u)];
    fpga_screen_goto(74,0);
    fpga_screen_putchar('!');
    CHECK(s_osd[addr_of(74u,0u,80u)]==(uint8_t)('!'+128u));
    CHECK(s_osd[addr_of(72u,0u,80u)]==originalLeft);
    CHECK(s_osd[addr_of(75u,0u,80u)]==(uint8_t)(msg[75]+128u));
    /* Partial string must also leave its neighboring bytes intact. */
    fpga_screen_goto(3,0);
    fpga_screen_puts("HIJ");
    CHECK(s_osd[addr_of(2u,0u,80u)]==(uint8_t)(msg[2]+128u));
    CHECK(s_osd[addr_of(3u,0u,80u)]==(uint8_t)('H'+128u));
    CHECK(s_osd[addr_of(5u,0u,80u)]==(uint8_t)('J'+128u));
    CHECK(s_osd[addr_of(6u,0u,80u)]==(uint8_t)(msg[6]+128u));

    /* Existing menu layout remains exactly 40 columns after a wide view. */
    fpga_screen_set_columns(FPGA_SCREEN_W);
    fpga_screen_clear();
    fpga_screen_puts("MENU");
    CHECK(s_osd[addr_of(1u,0u,40u)]==(uint8_t)('E'+128u));
    CHECK(s_osd[addr_of(1u,0u,40u)+1u]==0xA0u);

    /* OSD log producers must never touch SPI or redraw video. */
    const unsigned before_log=s_writes+s_fills+s_reg_writes;
    osd_log("MCU JUKE: LOW HEAP FOR TRACK 494 (CHUNKS=12)");
    CHECK(s_writes+s_fills+s_reg_writes==before_log);
    CHECK(strstr(s_last_tee,"(CHUNKS=12)")!=NULL);
    osd_console_show();
    CHECK(fpga_screen_columns()==80u);
    CHECK(s_regs[0x17]==1u && s_regs[0x10]==1u && s_regs[0x11]==1u);
    char snapshot[OSD_CONSOLE_ROWS][OSD_CONSOLE_LINE_CAP];
    CHECK(osd_console_snapshot(snapshot,OSD_CONSOLE_ROWS)==1);
    CHECK(strstr(snapshot[0],"(CHUNKS=12)")!=NULL);
    const char *expected=snapshot[0];
    for(unsigned i=0;expected[i];i++)
        CHECK(s_osd[addr_of(i,0u,80u)]==(uint8_t)(expected[i]+128u));

    /* 79-character screen budget retains the end of long diagnostics
     * within the Apple II 80th-column auto-wrap boundary. */
    char longmsg[100];
    memset(longmsg,'X',sizeof(longmsg));
    longmsg[sizeof(longmsg)-1]=0;
    osd_log("%s",longmsg);
    CHECK(strlen(s_last_tee)==OSD_CONSOLE_COLS);
    CHECK(osd_console_snapshot(snapshot,OSD_CONSOLE_ROWS)==2);
    CHECK(strlen(snapshot[1])==OSD_CONSOLE_COLS);
    const unsigned before_idle=s_writes+s_fills;
    osd_console_service();
    CHECK(s_writes+s_fills==before_idle);
    s_now=1000001u;
    osd_console_service();
    CHECK(s_writes+s_fills>before_idle);
    CHECK(s_reg_writes==3u); /* no video register writes on periodic repaint */

    osd_console_set_lockout(true);
    const unsigned before_lock=s_writes+s_fills+s_reg_writes;
    osd_log("HIDDEN AFTER LOCKOUT");
    osd_console_show();
    osd_console_service();
    CHECK(s_writes+s_fills+s_reg_writes==before_lock);
    osd_console_set_lockout(false);
    osd_console_hide();
    CHECK(s_regs[0x10]==0u); /* native Apple video returned */
    CHECK(s_mutex_take==s_mutex_give);
    CHECK(s_tee==3u);
    puts("PASS M3 OSD80: 40/80 SDRAM layout, aligned complete-word writes, "
         "full diagnostic snapshots, throttled repaint, view lockout");
    return 0;
}
