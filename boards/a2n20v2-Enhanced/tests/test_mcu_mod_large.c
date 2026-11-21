/* Standalone J2 MOD parser, 1-MiB sample staging and parity test.
 * No Bouffalo SDK needed: SPI SPACE1 is emulated in host RAM. */
#include "mcu_mod_format.h"
#include "mcu_mod_sample_store.h"
#include "fpga_spi.h"
#include "hxcmod.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#define PATTERN_BYTES 1024u
#define HDR 1084u
#define NSAMPLES 8u
#define SMP_BYTES (NSAMPLES*131070u)
#define FILE_BYTES (HDR+PATTERN_BYTES+SMP_BYTES)
static uint8_t fixture[FILE_BYTES],fake_sdram[MOD_SDRAM_CAPACITY];
static msample reference[512],streamed[512];
static modcontext normal_ctx,external_ctx;
static void ck(int cond,const char *what)
{
    if(!cond){fprintf(stderr,"FAIL J2: %s\n",what);exit(1);}
}
/* Emulated FPGA: bounds-check every SPI transfer, especially cache miss. */
void fpga_spi_xfer_write(uint8_t space,uint32_t address,
                         const uint8_t *data,uint16_t len)
{
    ck(space==FPGA_SPACE_SDRAM,"SPI write wrong space");
    ck(address>=MOD_SDRAM_BASE &&
       address-MOD_SDRAM_BASE<=MOD_SDRAM_CAPACITY-len,
       "SPI write outside reserved region");
    memcpy(fake_sdram+address-MOD_SDRAM_BASE,data,len);
}
void fpga_spi_xfer_read(uint8_t space,uint32_t address,
                        uint8_t *data,uint16_t len)
{
    ck(space==FPGA_SPACE_SDRAM,"SPI read wrong space");
    ck(address>=MOD_SDRAM_BASE &&
       address-MOD_SDRAM_BASE<=MOD_SDRAM_CAPACITY-len,
       "SPI read outside reserved region");
    memcpy(data,fake_sdram+address-MOD_SDRAM_BASE,len);
}
int main(void)
{
    mod_format_t fmt;
    memset(fixture,0,sizeof fixture);
    memcpy(fixture,"J2 FPGA SDRAM PARITY",20);
    fixture[950]=1;
    memcpy(fixture+1080,"M.K.",4);
    for(unsigned i=0;i<NSAMPLES;i++){
        unsigned h=20u+i*30u;
        fixture[h+22]=0xff;fixture[h+23]=0xff; /* 65535 words */
        fixture[h+25]=64;
        fixture[h+29]=1;
    }
    /* Sample #1, note period 428 (C-3) in L and R channels. */
    fixture[1084]=0x01;fixture[1085]=0xAC;
    fixture[1086]=0x10;fixture[1087]=0x00;
    fixture[1088]=0x01;fixture[1089]=0xAC;
    fixture[1090]=0x10;fixture[1091]=0x00;
    for(unsigned i=0;i<SMP_BYTES;i++)
        fixture[HDR+PATTERN_BYTES+i]=(uint8_t)((i*11u+31u)&255u);
    ck(mod_format_probe(fixture,sizeof fixture,&fmt),"1-MiB format");
    ck(fmt.prefix_bytes==HDR+PATTERN_BYTES,"pattern prefix");
    ck(fmt.sample_bytes==SMP_BYTES,"total waveform length");
    ck(mod_store_begin(fmt.lengths),"2-MiB sample region allocation");
    for(uint32_t at=0;at<fmt.sample_bytes;) {
        uint16_t n=(uint16_t)((fmt.sample_bytes-at)>4096u?4096u:fmt.sample_bytes-at);
        ck(mod_store_stage(at,fixture+fmt.prefix_bytes+at,n),"stage");
        at+=n;
    }
    ck(!memcmp(fake_sdram,fixture+fmt.prefix_bytes,fmt.sample_bytes),
       "complete 1-MiB sample store parity");
    ck(hxcmod_init(&normal_ctx) && hxcmod_setcfg(&normal_ctx,44100,100,1),
       "init regular HxCMOD");
    ck(hxcmod_load(&normal_ctx,fixture,sizeof fixture),
       "load regular HxCMOD");
    ck(hxcmod_init(&external_ctx) && hxcmod_setcfg(&external_ctx,44100,100,1),
       "init external HxCMOD");
    hxcmod_external_samples(&external_ctx,MOD_SDRAM_BASE,
                            MOD_SDRAM_CAPACITY,NULL,mod_store_read,mod_store_write);
    ck(hxcmod_load(&external_ctx,fixture,(int)fmt.prefix_bytes),
       "load header/pattern-only HxCMOD");
    for(unsigned t=0;t<250;t++) {
        hxcmod_fillbuffer(&normal_ctx,reference,256,NULL);
        hxcmod_fillbuffer(&external_ctx,streamed,256,NULL);
        ck(!memcmp(reference,streamed,sizeof reference),"44.1k PCM parity");
    }
    ck(mod_store_misses()>0 && mod_store_faults()==0,
       "cache miss statistics and bounds");
    hxcmod_unload(&normal_ctx);
    hxcmod_unload(&external_ctx);
    /* Bad files must be rejected BEFORE calling the HxCMOD decoder. */
    ck(!mod_format_probe(fixture,fmt.prefix_bytes+fmt.sample_bytes-1u,&fmt),
       "truncated sample body rejected");
    fixture[950]=0;
    ck(!mod_format_probe(fixture,sizeof fixture,&fmt),
       "zero song length rejected");
    printf("PASS J2: 1-MiB MOD staged; direct/SDRAM HxCMOD stereo PCM identical, %u cache misses\n",
           (unsigned)mod_store_misses());
    return 0;
}
