/* M3: exercise ACTUAL shared fpga_spi.c fast SD RAM portal implementation.
 * 4 x 128B frames must release CS/mutex between frames, exact dummy
 * alignment, full-sector first-use comparison against bytewise XFER,
 * automatic permanent fallback if a bulk SPI read is corrupted.
 *
 * This is a protocol/driver mock, not a replacement for RTL or hardware.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "bflb_gpio.h"
#include "bflb_spi.h"
#include "bflb_mtimer.h"
#include "fpga_spi.h"
#define CHECK(c) do {if(!(c)){fprintf(stderr,"FAIL M3 SPI line %d: %s\n",__LINE__,#c);exit(1);}}while(0)
static struct bflb_device_s gpio_dev,spi_dev;
static struct bflb_spi_config_s config;
static uint8_t card_sector[512],header[7];
static unsigned bytepos,frame_len,frame_addr,frame_space,frame_read;
static bool cs_active,force_corrupt_bulk;
static unsigned large_calls,frames,max_frame,read_frames,burst_reads,bytewise_reads;
static unsigned mismatched_bytes;
static unsigned total_calls;
struct bflb_device_s *bflb_device_get_by_name(const char *name)
{
    CHECK(!strcmp(name,"gpio") || !strcmp(name,"spi0"));
    return !strcmp(name,"gpio")?&gpio_dev:&spi_dev;
}
void bflb_gpio_init(struct bflb_device_s *d,uint32_t pin,uint32_t mode)
{(void)d;(void)pin;(void)mode;}
void bflb_gpio_set(struct bflb_device_s *d,uint32_t pin)
{
    (void)d;
    if(pin!=GPIO_PIN_0 || !cs_active)return;
    CHECK(bytepos==7u+1u+frame_len);
    CHECK(frame_read && frame_space==FPGA_SPACE_LOCAL);
    CHECK(frame_addr>=FPGA_SD_BURST_WINDOW_ADDR);
    CHECK(frame_addr+frame_len<=FPGA_SD_BURST_WINDOW_ADDR+512u);
    cs_active=false;frames++;read_frames++;
}
void bflb_gpio_reset(struct bflb_device_s *d,uint32_t pin)
{
    (void)d;
    CHECK(pin==GPIO_PIN_0 && !cs_active);
    cs_active=true;bytepos=frame_len=frame_addr=frame_space=frame_read=0;
}
void bflb_spi_init(struct bflb_device_s *d,const struct bflb_spi_config_s *c)
{CHECK(d==&spi_dev);config=*c;}
uint64_t bflb_mtimer_get_time_ms(void){return 0;}
void bflb_mtimer_delay_ms(uint32_t ms){(void)ms;}
void bflb_mtimer_delay_us(uint32_t us){CHECK(us<=3u);}
static uint8_t wire_byte(uint8_t tx)
{
    CHECK(cs_active);
    if(bytepos<7u) {
        header[bytepos++]=tx;
        if(bytepos==7u) {
            CHECK(header[0]==0x7f && (header[1]&0xF0u)==0x10);
            frame_space=(header[1]>>1)&7u;
            frame_read=header[1]&1u;
            frame_addr=header[2]|(header[3]<<8)|(header[4]<<16);
            frame_len=header[5]|(header[6]<<8);
            CHECK(frame_len==128u);
            CHECK(frame_space==FPGA_SPACE_LOCAL && frame_read);
        }
        return 0xa5;
    }
    const unsigned pos=bytepos++-7u;
    CHECK(tx==0xffu);
    if(pos==0u)return 0x5a; /* mandatory one-byte read dummy */
    CHECK(pos-1u<frame_len);
    return card_sector[frame_addr-FPGA_SD_BURST_WINDOW_ADDR+pos-1u];
}
int bflb_spi_poll_exchange(struct bflb_device_s *d,const uint8_t *tx,
                           uint8_t *rx,uint32_t n)
{
    CHECK(d==&spi_dev && tx && rx && n && n<=520u);
    total_calls++;
    if(n>1u) {
        large_calls++;
        CHECK(n==136u); /* 7 header + 1 dummy + 128 SD bytes */
        if(n>max_frame)max_frame=n;
    }
    for(uint32_t i=0;i<n;i++)rx[i]=wire_byte(tx[i]);
    if(n>1u && force_corrupt_bulk) {
        rx[8u+33u]^=0x80u; /* simulate 20MHz bad read alignment/timing */
        mismatched_bytes++;
    }
    if(n>1u)burst_reads++;
    else bytewise_reads++;
    return 0;
}
void fpga_screen_clear(void){}
void fpga_screen_puts(const char *s){(void)s;}
int main(int argc,char **argv)
{
    force_corrupt_bulk=(argc>1 && !strcmp(argv[1],"--corrupt"));
    for(unsigned i=0;i<512u;i++)
        card_sector[i]=(uint8_t)((i*37u + (i>>3u))^0x95u);
    fpga_spi_init();
    CHECK(config.freq==20000000u && config.mode==SPI_MODE1);
    uint8_t dest[512];
    memset(dest,0,sizeof dest);
    fpga_spi_sd_burst_buffer_read(dest);
    CHECK(!memcmp(dest,card_sector,512));
    CHECK(frames==8u && burst_reads==4u && bytewise_reads==4u*136u);
    CHECK(max_frame==136u && total_calls==4u+4u*136u);
    CHECK(fpga_spi_sd_burst_bulk_ok()==!force_corrupt_bulk);
    if(force_corrupt_bulk)CHECK(mismatched_bytes==4u);
    memset(dest,0,sizeof dest);
    fpga_spi_sd_burst_buffer_read(dest);
    CHECK(!memcmp(dest,card_sector,512));
    CHECK(frames==12u);
    CHECK(burst_reads==(force_corrupt_bulk?4u:8u));
    CHECK(bytewise_reads==(force_corrupt_bulk?8u*136u:4u*136u));
    CHECK(!cs_active);
    printf("PASS M3 SD portal %s: 512B exact, 4x128 interleaved frames, 1st-sector A/B guard\n",
           force_corrupt_bulk?"corrupt-bulk auto-fallback":"fast bulk");
    return 0;
}
