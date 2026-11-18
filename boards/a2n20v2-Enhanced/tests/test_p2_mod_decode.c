/* SenseiPlay8 P2 runtime parser — actual source, synthetic MOD fixture.
 * No copyright-covered MOD content is in the repository.
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "sensei_mod_decode.h"

static uint8_t fixture[1084+1024+256];
static uint8_t pcm[49152];
static sensei_mod_decoded_t mod;

static void require(int cond,const char *why)
{
    if(!cond){fprintf(stderr,"FAIL P2 parser: %s\n",why);exit(1);}
}

int main(void)
{
    memset(fixture,0,sizeof fixture);
    memcpy(fixture,"RUNTIME SYNTHETIC MOD",21);
    memcpy(fixture+1080,"M.K.",4);
    fixture[950]=1; fixture[952]=0;
    /* instrument 1: 256-byte sample, default volume 48, full loop */
    fixture[20+22]=0;fixture[20+23]=128;
    fixture[20+25]=48;
    fixture[20+28]=0;fixture[20+29]=128;
    /* first row, channel 0, instrument 1, period 428 */
    fixture[1084]=0x01;
    fixture[1085]=0xAC;
    fixture[1086]=0x10;
    for(unsigned i=0;i<256;i++)fixture[1084+1024+i]=(uint8_t)i;
    require(sensei_mod_decode(fixture,sizeof fixture,NULL,0,&mod),
            "dry-run MOD sizing rejected");
    require(mod.doc_pcm_bytes==256,"dry-run DOC sample size wrong");
    require(sensei_mod_decode(fixture,sizeof fixture,pcm,256,&mod),
            "exact-sized DOC PCM buffer rejected");
    require(mod.order_count==1 && mod.pattern_count==1,"order metadata");
    require(mod.pattern_offset==1084 && mod.file_sample_bytes==256,"offsets");
    require(mod.doc_pcm_bytes==256 && mod.catalog[7]==48,"sample bank/catalog");
    require(pcm[0]==0x80 && pcm[1]==0x81 && pcm[255]==0x7f,
            "signed MOD PCM to DOC bytes");
    puts("PASS P2 parser: original MOD header, order table and DOC instrument");
    require(!sensei_mod_decode(fixture,1083,pcm,sizeof pcm,&mod),
            "accepts truncated MOD");
    fixture[1080]='X';
    require(!sensei_mod_decode(fixture,sizeof fixture,pcm,sizeof pcm,&mod),
            "accepts invalid channel signature");
    fixture[1080]='M';
    require(!sensei_mod_decode(fixture,sizeof fixture,pcm,128,&mod),
            "ignores DOC bank capacity");
    puts("PASS P2 parser: malformed file and sample-RAM budget refused");
    return 0;
}
