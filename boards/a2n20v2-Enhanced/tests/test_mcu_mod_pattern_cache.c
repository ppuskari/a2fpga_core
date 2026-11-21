/* J2R7: validate the 8-KiB LRU cache with 4/6/8 channels plus the
 * J2R6 48-pattern 8CHN / SoundTracker HxCMOD PCM parity against external
 * SDRAM sample bank. No hardware/SDK required: SPI SPACE1 is byte RAM. */
#include "mcu_mod_format.h"
#include "mcu_mod_pattern_store.h"
#include "mcu_mod_sample_store.h"
#include "fpga_spi.h"
#include "hxcmod.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define PATS 48u
#define VOICES 8u
#define PATLEN (256u*VOICES)
#define HEADER 1084u
#define SAMPLE_LEN 1024u
#define FILE_LEN (HEADER+PATS*PATLEN+SAMPLE_LEN)
#define TEST_SDRAM_BYTES (MOD_PATTERN_SDRAM_BASE+MOD_PATTERN_SDRAM_CAPACITY-MOD_SDRAM_BASE)
static uint8_t file[FILE_LEN], sdram[TEST_SDRAM_BYTES];
static modcontext direct, external;
static msample reference_pcm[512], streamed_pcm[512];

static void ck(int yes,const char *msg) {
    if(!yes) { fprintf(stderr,"FAIL J2R6: %s\n",msg); exit(1); }
}
void fpga_spi_xfer_write(uint8_t space,uint32_t addr,const uint8_t *p,uint16_t n)
{
    ck(space==FPGA_SPACE_SDRAM && addr>=MOD_SDRAM_BASE &&
       addr-MOD_SDRAM_BASE<=sizeof sdram-n,"SPI write SDRAM range");
    memcpy(sdram+addr-MOD_SDRAM_BASE,p,n);
}
void fpga_spi_xfer_read(uint8_t space,uint32_t addr,uint8_t *p,uint16_t n)
{
    ck(space==FPGA_SPACE_SDRAM && addr>=MOD_SDRAM_BASE &&
       addr-MOD_SDRAM_BASE<=sizeof sdram-n,"SPI read SDRAM range");
    memcpy(p,sdram+addr-MOD_SDRAM_BASE,n);
}

/* Verify sixteen 1-KiB pages serve both pattern sizes efficiently. The
 * same 16384B must hold 16 x 4CH or 8 x 6/8CH with bounded LRU eviction. */
static void run_16k_lru(unsigned channels,unsigned resident_patterns)
{
    enum { N=17u, MAX_PATTERN=2048u };
    static uint8_t patterns[N*MAX_PATTERN];
    const unsigned len=256u*channels;
    ck(mod_patterns_begin(channels,resident_patterns+1u),"16K begin");
    for(unsigned p=0;p<resident_patterns+1u;p++) {
        memset(patterns+p*MAX_PATTERN,(int)(p+1u),len);
        ck(mod_patterns_stage(p*len,patterns+p*MAX_PATTERN,(uint16_t)len),
           "16K pattern staging");
    }
    for(unsigned p=0;p<resident_patterns;p++) {
        note *n=mod_patterns_get(NULL,p,channels);
        ck(((const uint8_t *)n)[0]==(uint8_t)(p+1u),"16K pattern identity");
    }
    ck(mod_patterns_fetch_count()==resident_patterns &&
       mod_patterns_evictions()==0u,"initial 16K residency");
    for(unsigned p=0;p<resident_patterns;p++) {
        note *n=mod_patterns_get(NULL,p,channels);
        ck(((const uint8_t *)n)[0]==(uint8_t)(p+1u),
           "16K hit preserved pattern");
    }
    ck(mod_patterns_cache_hits()==resident_patterns &&
       mod_patterns_fetch_count()==resident_patterns &&
       mod_patterns_evictions()==0u,"16K hit without SPI refill");
    ck(((const uint8_t *)mod_patterns_get(
         NULL,resident_patterns,channels))[0]==(uint8_t)(resident_patterns+1u),
       "16K first LRU eviction read");
    ck(mod_patterns_fetch_count()==resident_patterns+1u &&
       mod_patterns_evictions()==1u,"LRU evicts just one resident pattern");
    ck(((const uint8_t *)mod_patterns_get(NULL,1u,channels))[0]==2u,
       "recently used cache slot unexpectedly evicted");
    ck(mod_patterns_fetch_count()==resident_patterns+1u,
       "LRU retained recently used pattern");
    ck(((const uint8_t *)mod_patterns_get(NULL,0u,channels))[0]==1u,
       "LRU reloaded oldest pattern");
    ck(mod_patterns_fetch_count()==resident_patterns+2u &&
       mod_patterns_evictions()==2u,"LRU oldest pattern reloaded");
    ck(mod_patterns_read_bytes()==(resident_patterns+2u)*len,
       "cache byte counters");
    ck(mod_patterns_faults()==0u,"no pattern-cache faults");
    printf("PASS J2R8: %uCH 16KiB LRU, %u resident, hits=%lu evicts=%lu\n",
           channels,resident_patterns,
           (unsigned long)mod_patterns_cache_hits(),
           (unsigned long)mod_patterns_evictions());
}

static void run_48_patterns(void)
{
    mod_format_t fmt;
    memset(file,0,sizeof file);
    memcpy(file,"J2R6 48 PATTERN CACHE",21);
    memcpy(file+1080,"8CHN",4);
    file[950]=PATS;
    for(unsigned p=0;p<PATS;p++) file[952+p]=(uint8_t)p;
    file[20+22]=2u; file[20+25]=64u; file[20+29]=1u;
    for(unsigned p=0;p<PATS;p++) {
        const unsigned pos=HEADER+p*PATLEN;
        for(unsigned ch=0;ch<VOICES;ch++) {
            const unsigned n=pos+ch*4u;
            file[n]=0x01u; file[n+1]=(uint8_t)(0xac+(p%3u));
            file[n+2]=0x10u; file[n+3]=0x00u;
        }
    }
    for(unsigned i=0;i<SAMPLE_LEN;i++)
        file[HEADER+PATS*PATLEN+i]=(uint8_t)(i*37u+17u);
    ck(mod_format_probe(file,sizeof file,&fmt),"48 pattern format");
    ck(fmt.pattern_bytes==PATS*PATLEN &&
       fmt.prefix_bytes==HEADER+PATS*PATLEN,"48 pattern layout");
    ck(mod_store_begin(fmt.lengths) &&
       mod_patterns_begin(fmt.channels,fmt.pattern_count),"48 pattern begin");
    for(unsigned off=0;off<fmt.pattern_bytes;off+=4096u) {
        const uint16_t n=(uint16_t)(fmt.pattern_bytes-off<4096u?
                                    fmt.pattern_bytes-off:4096u);
        ck(mod_patterns_stage(off,file+HEADER+off,n),"stage pattern payload");
    }
    ck(mod_patterns_verify(0,file+HEADER,32u) &&
       mod_patterns_verify(fmt.pattern_bytes-32,
                           file+fmt.prefix_bytes-32,32u),"pattern readback");
    ck(mod_store_stage(0,file+fmt.prefix_bytes,SAMPLE_LEN),"sample stage");
    ck(hxcmod_init(&direct) && hxcmod_setcfg(&direct,44100,100,1) &&
       hxcmod_load(&direct,file,sizeof file),"direct 48-pattern decoder");
    ck(hxcmod_init(&external) && hxcmod_setcfg(&external,44100,100,1),
       "external 48-pattern decoder");
    hxcmod_external_samples(&external,MOD_SDRAM_BASE,
                            MOD_SDRAM_CAPACITY,NULL,mod_store_read,mod_store_write);
    hxcmod_external_patterns(&external,fmt.pattern_bytes,NULL,mod_patterns_get);
    ck(hxcmod_load(&external,file,HEADER),"header-only 48-pattern load");
    ck(external.number_of_channels==8,"8ch loaded");
    for(unsigned p=0;p<PATS;p++) {
        /* Force each pattern transition at a row boundary. The renderer
         * must fetch the requested bank entry before interpreting notes. */
        direct.tablepos=external.tablepos=(muint)p;
        direct.patternpos=external.patternpos=0;
        direct.patternticks=direct.patternticksaim+1;
        external.patternticks=external.patternticksaim+1;
        for(unsigned n=0;n<4;n++) {
            hxcmod_fillbuffer(&direct,reference_pcm,256,NULL);
            hxcmod_fillbuffer(&external,streamed_pcm,256,NULL);
            ck(!memcmp(reference_pcm,streamed_pcm,sizeof reference_pcm),
               "48-pattern FPGA/cached PCM differs from direct memory");
        }
    }
    ck(mod_patterns_fetch_count()>=PATS,"patterns not swapped");
    ck(mod_patterns_read_bytes()>=fmt.pattern_bytes,"pattern read bytes");
    ck(mod_patterns_faults()==0,"pattern cache invalid accesses");
    ck(mod_store_faults()==0,"sample cache faults");
    printf("PASS J2R6: 48 x 8CHN patterns, %lu staged, %lu read, %lu fills\n",
           (unsigned long)fmt.pattern_bytes,
           (unsigned long)mod_patterns_read_bytes(),
           (unsigned long)mod_patterns_fetch_count());
}

static void run_15_sample(void)
{
    enum { HDR15=600u, PAT15=1024u, SMP15=512u, FILE15=HDR15+PAT15+SMP15 };
    uint8_t f[FILE15];
    mod_format_t fmt;
    memset(f,0,sizeof f);
    memcpy(f,"15-SAMPLE PROBE",15);
    f[20+22]=1u; f[20+25]=64u; f[20+29]=1u; /* 512B sample */
    f[470]=1u; f[472]=0u;                   /* one order, pattern zero */
    f[HDR15]=0x01u; f[HDR15+1u]=0xacu;
    f[HDR15+2u]=0x10u; f[HDR15+3u]=0u;
    for(unsigned i=0;i<SMP15;i++)
        f[HDR15+PAT15+i]=(uint8_t)(i*13u+7u);
    ck(mod_format_probe(f,FILE15,&fmt) &&
       fmt.header_bytes==HDR15 && fmt.channels==4u,"SoundTracker 15 layout");
    ck(mod_store_begin(fmt.lengths) &&
       mod_patterns_begin(fmt.channels,fmt.pattern_count),"15 begin");
    /* Header probe has consumed 484 bytes of the first 1024-byte pattern. */
    ck(mod_patterns_stage(0,f+HDR15,HEADER-HDR15),"15 preloaded pattern");
    ck(mod_patterns_stage(HEADER-HDR15,f+HEADER,PAT15-(HEADER-HDR15)),
       "15 remaining pattern");
    ck(mod_patterns_verify(0,f+HDR15,32) &&
       mod_patterns_verify(PAT15-32,f+HDR15+PAT15-32,32),"15 verify");
    ck(mod_store_stage(0,f+HDR15+PAT15,SMP15),"15 samples");
    ck(hxcmod_init(&direct) && hxcmod_setcfg(&direct,44100,100,1) &&
       hxcmod_load(&direct,f,FILE15),"15 reference");
    ck(hxcmod_init(&external) && hxcmod_setcfg(&external,44100,100,1),
       "15 external init");
    hxcmod_external_samples(&external,MOD_SDRAM_BASE,
                            MOD_SDRAM_CAPACITY,NULL,mod_store_read,mod_store_write);
    hxcmod_external_patterns(&external,fmt.pattern_bytes,NULL,mod_patterns_get);
    ck(hxcmod_load(&external,f,HEADER),"15 header-only load");
    for(unsigned n=0;n<80;n++) {
        hxcmod_fillbuffer(&direct,reference_pcm,256,NULL);
        hxcmod_fillbuffer(&external,streamed_pcm,256,NULL);
        ck(!memcmp(reference_pcm,streamed_pcm,sizeof reference_pcm),
           "SoundTracker 15 pattern-cache PCM parity");
    }
    ck(mod_patterns_faults()==0 && mod_store_faults()==0,"15 cache faults");
    printf("PASS J2R6: SoundTracker 15-instrument header + cached pattern parity\n");
}

int main(void)
{
    ck(mod_patterns_begin(8,128),"max 8CH 128 patterns");
    ck(mod_patterns_bytes()==MOD_PATTERN_SDRAM_CAPACITY,"256KiB limit");
    ck(!mod_patterns_begin(8,129),"129 patterns must be rejected");
    ck(MOD_PATTERN_CACHE_BYTES==16384u,"16 KiB cache layout");
    run_16k_lru(4u,16u);
    run_16k_lru(6u,8u);
    run_16k_lru(8u,8u);
    run_48_patterns();
    run_15_sample();
    return 0;
}
