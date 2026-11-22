/* J2R9: Exercise the ACTUAL BL616 fpga_spi.c through a byte-stream
 * FPGA XFER model, compiled twice: bulk MOD/PCM transfers and bytewise
 * fallback. Detect address/length mistakes, read dummy alignment, chunk
 * boundaries and any accidental bulk on unrelated FPGA spaces.
 *
 * The C mock models protocol bytes, not physical FPGA SCLK/CDC timing.
 * Hardware validation on the Tang Nano 20K is still mandatory.
 */
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "bflb_gpio.h"
#include "bflb_spi.h"
#include "bflb_mtimer.h"
#include "fpga_spi.h"

#define MUST(x) do { if(!(x)) { \
    fprintf(stderr,"FAIL J2R9 SPI line %d: %s\n",__LINE__,#x); exit(1); \
} } while (0)
static struct bflb_device_s s_gpio,s_spi;
static uint8_t s_samples[16384],s_patterns[4096],s_pcm[2048],s_local[1024];
static uint8_t s_header[7];
static uint32_t s_addr,s_len,s_pos;
static unsigned s_space,s_read;
static bool s_cs;
static uint64_t s_calls,s_large_calls,s_chunks,s_hold_us;
static uint64_t s_sdram_large_calls,s_pcm_large_calls,s_unrelated_large_calls;
static uint32_t s_max_len;
static struct bflb_spi_config_s s_config;

struct bflb_device_s *bflb_device_get_by_name(const char *name)
{
    MUST(!strcmp(name,"gpio") || !strcmp(name,"spi0"));
    return !strcmp(name,"gpio")?&s_gpio:&s_spi;
}
void bflb_gpio_init(struct bflb_device_s *d,uint32_t pin,uint32_t mode)
{ (void)d; (void)pin; (void)mode; }
void bflb_gpio_set(struct bflb_device_s *d,uint32_t pin)
{
    (void)d;
    if(pin!=GPIO_PIN_0)return;
    if(!s_cs)return; /* Initial CS# deassert in fpga_spi_init. */
    MUST(s_pos==7u+s_len+(s_read?1u:0u));
    s_cs=false;
    ++s_chunks;
}
void bflb_gpio_reset(struct bflb_device_s *d,uint32_t pin)
{
    (void)d;
    MUST(pin==GPIO_PIN_0 && !s_cs);
    s_cs=true;s_pos=0;s_read=0;s_len=0;s_addr=0;s_space=0;
}
void bflb_spi_init(struct bflb_device_s *d,const struct bflb_spi_config_s *cfg)
{
    MUST(d==&s_spi);
    s_config=*cfg;
}
uint64_t bflb_mtimer_get_time_ms(void) { return 0; }
void bflb_mtimer_delay_ms(uint32_t ms) { (void)ms; }
void bflb_mtimer_delay_us(uint32_t us) { s_hold_us+=us; }

static uint8_t *memory_byte(unsigned space,uint32_t address)
{
    if(space==FPGA_SPACE_SDRAM) {
        if(address>=0x400000u && address<0x404000u)
            return &s_samples[address-0x400000u];
        if(address>=0x600000u && address<0x601000u)
            return &s_patterns[address-0x600000u];
    } else if(space==FPGA_SPACE_PCM && address<sizeof s_pcm) {
        return &s_pcm[address];
    } else if(space==FPGA_SPACE_LOCAL && address<sizeof s_local) {
        return &s_local[address];
    }
    MUST(0 && "unexpected memory space/address");
    return NULL;
}
static uint8_t wire_byte(uint8_t tx)
{
    MUST(s_cs);
    if(s_pos<7u) {
        s_header[s_pos++]=tx;
        if(s_pos==7u) {
            MUST(s_header[0]==0x7Fu);
            MUST((s_header[1]&0xF0u)==0x10u);
            s_read=s_header[1]&1u;
            s_space=(s_header[1]>>1)&7u;
            s_addr=(uint32_t)s_header[2] |
                   ((uint32_t)s_header[3]<<8) |
                   ((uint32_t)s_header[4]<<16);
            s_len=(uint32_t)s_header[5] | ((uint32_t)s_header[6]<<8);
            MUST(s_len>0u && s_len<=512u);
            MUST(s_space<=7u);
        }
        return 0xA5;
    }
    uint32_t i=s_pos++-7u;
    if(s_read) {
        if(i==0u)return 0x5A; /* Must drop the mandatory dummy byte. */
        --i;
        MUST(i<s_len);
        return *memory_byte(s_space,s_addr+i);
    }
    MUST(i<s_len);
    *memory_byte(s_space,s_addr+i)=tx;
    return 0xC3;
}
int bflb_spi_poll_exchange(struct bflb_device_s *d,const uint8_t *tx,
                           uint8_t *rx,uint32_t n)
{
    MUST(d==&s_spi && tx && rx && n>0u && n<=520u);
    ++s_calls;
    if(n>1u)++s_large_calls;
    if(n>s_max_len)s_max_len=n;
    for(uint32_t i=0;i<n;i++)rx[i]=wire_byte(tx[i]);
    if(n>1u) {
        if(s_space==FPGA_SPACE_SDRAM) ++s_sdram_large_calls;
        else if(s_space==FPGA_SPACE_PCM) ++s_pcm_large_calls;
        else ++s_unrelated_large_calls;
    }
    return 0;
}
void fpga_screen_clear(void) {}
void fpga_screen_puts(const char *s) { (void)s; }

static void check_pair(unsigned space,uint32_t addr,uint32_t size)
{
    static uint8_t input[16384],output[16384];
    MUST(size<=sizeof input);
    for(uint32_t i=0;i<size;i++)
        input[i]=(uint8_t)((i*73u+(i>>4)+addr)>>1);
    memset(output,0xCC,size);
    fpga_spi_xfer_write((uint8_t)space,addr,input,(uint16_t)size);
    if(space!=FPGA_SPACE_PCM) {
        fpga_spi_xfer_read((uint8_t)space,addr,output,(uint16_t)size);
        MUST(memcmp(input,output,size)==0);
    } else {
        MUST(memcmp(input,s_pcm,size)==0);
    }
}
int main(void)
{
    fpga_spi_init();
    MUST(s_config.freq==20000000u && s_config.mode==SPI_MODE1);
    check_pair(FPGA_SPACE_SDRAM,0x400000u,8192u); /* 8 KiB sample page */
    check_pair(FPGA_SPACE_SDRAM,0x600000u,2048u); /* 8CH MOD pattern */
    check_pair(FPGA_SPACE_SDRAM,0x401223u,773u); /* partial and odd address */
    check_pair(FPGA_SPACE_PCM,0u,1024u);         /* 256 stereo HDMI frames */
    /* Non-MOD spaces MUST remain bytewise even in a bulk build. */
    uint64_t before=s_large_calls;
    check_pair(FPGA_SPACE_LOCAL,0x23u,129u);
    MUST(s_large_calls==before);
    uint8_t extra[65];memset(extra,0x89,sizeof extra);
    before=s_large_calls;
    fpga_spi_xfer_fill(FPGA_SPACE_LOCAL,0x100u,0x89u,sizeof extra);
    MUST(memcmp(&s_local[0x100u],extra,sizeof extra)==0);
    MUST(s_large_calls==before);
    MUST(!s_cs);
    MUST(s_unrelated_large_calls==0u);
#if FPGA_SPI_MOD_BULK_XFER && !FPGA_SPI_MOD_BULK_SDRAM
    MUST(s_pcm_large_calls==2u); /* exactly two 512B PCM payloads */
    MUST(s_sdram_large_calls==0u);
    MUST(s_large_calls==2u && s_max_len==519u);
    MUST(s_hold_us==6u);
#elif FPGA_SPI_MOD_BULK_XFER && FPGA_SPI_MOD_BULK_SDRAM
    /* Retain a simulation-only check of the failed physical transport mode
     * so the mock's inability to model real FPGA latency stays explicit. */
    MUST(s_pcm_large_calls==2u && s_sdram_large_calls>0u);
    MUST(s_large_calls>2u && s_max_len==520u);
    MUST(s_hold_us>=6u);
#else
    MUST(s_large_calls==0u && s_max_len==1u);
#endif
    printf("PASS J2R9a SPI %s: byte-exact SDRAM, PCM, dummy, chunks, fallback; "
           "%llu calls, %llu PCM bursts, %llu SDRAM bursts, %llu CS frames\n",
#if FPGA_SPI_MOD_BULK_XFER && !FPGA_SPI_MOD_BULK_SDRAM
           "PCM-ONLY",
#elif FPGA_SPI_MOD_BULK_XFER && FPGA_SPI_MOD_BULK_SDRAM
           "BULK-ALL-LAB",
#else
           "LEGACY",
#endif
           (unsigned long long)s_calls,(unsigned long long)s_pcm_large_calls,
           (unsigned long long)s_sdram_large_calls,
           (unsigned long long)s_chunks);
    return 0;
}
