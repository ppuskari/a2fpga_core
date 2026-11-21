/* J2R3: HxCMOD native 4/6/8 channel parsing and FPGA sample parity.
 * No SDK: FPGA SPI1 is emulated in RAM. Uses real HxCMOD decoder. */
#include "mcu_mod_format.h"
#include "mcu_mod_sample_store.h"
#include "fpga_spi.h"
#include "hxcmod.h"
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#define HEADER 1084u
#define SAMPLEN 1024u
#define MAX_PATBYTES (256u*8u)
static uint8_t file[HEADER+MAX_PATBYTES+SAMPLEN];
static uint8_t fake_sdram[MOD_SDRAM_CAPACITY];
static modcontext reference_ctx,virtual_ctx;
static msample pcm_ref[2*256],pcm_virtual[2*256];

static void require(int ok,const char *msg)
{
    if(!ok){fprintf(stderr,"FAIL J2R3 channels: %s\n",msg);exit(1);}
}
void fpga_spi_xfer_write(uint8_t space,uint32_t address,
                         const uint8_t *data,uint16_t len)
{
    require(space==FPGA_SPACE_SDRAM,"write SPI space");
    require(address>=MOD_SDRAM_BASE &&
            address-MOD_SDRAM_BASE<=MOD_SDRAM_CAPACITY-len,"write SDRAM bounds");
    memcpy(fake_sdram+address-MOD_SDRAM_BASE,data,len);
}
void fpga_spi_xfer_read(uint8_t space,uint32_t address,uint8_t *data,
                        uint16_t len)
{
    require(space==FPGA_SPACE_SDRAM,"read SPI space");
    require(address>=MOD_SDRAM_BASE &&
            address-MOD_SDRAM_BASE<=MOD_SDRAM_CAPACITY-len,"read SDRAM bounds");
    memcpy(data,fake_sdram+address-MOD_SDRAM_BASE,len);
}
static void run(const char sig[4],unsigned voices)
{
    mod_format_t fmt;
    memset(file,0,sizeof file);
    memcpy(file,"J2R3 CHANNEL PARITY",19);
    memcpy(file+1080,sig,4u);
    file[950]=1u;
    /* 512 words = 1024 sample bytes; valid sample #1. */
    file[20+22]=2u;
    file[20+23]=0u;
    file[20+25]=64u;
    file[20+29]=1u;
    const uint32_t patterns=256u*voices;
    const uint32_t bytes=HEADER+patterns+SAMPLEN;
    for(unsigned ch=0;ch<voices;ch++) {
        uint32_t i=HEADER+ch*4u;  /* row zero, channels 0..N-1 */
        file[i+0]=0x01;
        file[i+1]=0xAC;  /* period 428 (C-3) */
        file[i+2]=0x10;  /* instrument 1 */
        file[i+3]=0x00;
    }
    for(unsigned i=0;i<SAMPLEN;i++)
        file[HEADER+patterns+i]=(uint8_t)((i*73u+91u)&255u);
    require(mod_format_probe(file,bytes,&fmt),"HxCMOD signature parser");
    require(fmt.channels==voices,"channel count");
    require(fmt.pattern_bytes==patterns,"pattern bytes not N*256");
    require(fmt.sample_bytes==SAMPLEN,"sample lengths");
    require(mod_store_begin(fmt.lengths),"external SDRAM allocation");
    require(mod_store_stage(0u,file+fmt.prefix_bytes,SAMPLEN),"stage sample");
    require(hxcmod_init(&reference_ctx) &&
            hxcmod_setcfg(&reference_ctx,44100,100,1),"init reference decoder");
    require(hxcmod_load(&reference_ctx,file,(int)bytes),"HxCMOD full load");
    require(hxcmod_init(&virtual_ctx) &&
            hxcmod_setcfg(&virtual_ctx,44100,100,1),"init virtual decoder");
    hxcmod_external_samples(&virtual_ctx,MOD_SDRAM_BASE,
                            MOD_SDRAM_CAPACITY,NULL,mod_store_read,mod_store_write);
    require(hxcmod_load(&virtual_ctx,file,(int)fmt.prefix_bytes),
            "HxCMOD patterns-only load");
    require(virtual_ctx.number_of_channels==voices,
            "HxCMOD signature interpreted differently");
    unsigned nonzero=0;
    for(unsigned n=0;n<30;n++) {
        hxcmod_fillbuffer(&reference_ctx,pcm_ref,256,NULL);
        hxcmod_fillbuffer(&virtual_ctx,pcm_virtual,256,NULL);
        require(!memcmp(pcm_ref,pcm_virtual,sizeof pcm_ref),
                "full-memory vs SDRAM-backed PCM differs");
        for(unsigned i=0;i<512;i++)
            if(pcm_ref[i])nonzero++;
    }
    require(nonzero>100u,"silent multichannel output");
    require(mod_store_faults()==0u,"bad sample read/cache");
    hxcmod_unload(&reference_ctx);
    hxcmod_unload(&virtual_ctx);
    printf("PASS J2R3: %.4s %u channels parity %u nonzero frames\n",
           sig,voices,nonzero);
}
int main(void)
{
    require(MOD_STORE_VOICES==8u,"8-voice SRAM cache not configured");
    run("M.K.",4);
    run("M!K!",4);
    run("M&K!",4);
    run("4CHN",4);
    run("6CHN",6);
    run("8CHN",8);
    run("OKTA",8);
    run("OCTA",8);
    run("FLT8",8);
    run("EXO8",8);
    run("CD81",8);
    run("TDZ8",8);
    run("FA08",8);
    /* Validating the *source* format matters: an unsupported 8ch signature
     * must not silently enter SoundTracker-15's four-channel fallback. */
    memset(file,0,sizeof file);
    memcpy(file,"Extended Module:",16);
    require(!mod_format_probe(file,sizeof file,&(mod_format_t){0}),"XM rejected");
    memset(file,0,sizeof file);
    memcpy(file,"IMPM",4);
    require(!mod_format_probe(file,sizeof file,&(mod_format_t){0}),"IT rejected");
    memset(file,0,sizeof file);
    memcpy(file+44,"SCRM",4);
    require(!mod_format_probe(file,sizeof file,&(mod_format_t){0}),"S3M rejected");
    return 0;
}
