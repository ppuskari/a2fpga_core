/*
 * P2AA end-to-end native NTP loader test, including fake FAT disk broker.
 * Proves one file + one PCM allocation, and no translated MOD shadow bank.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "disk.h"
#include "sensei_runtime.h"

enum { FILE_BYTES=1326, TRACK_OFF=14, INST_OFF=26,
       ORDER_OFF=45, PAT_OFF=46, PCM_OFF=1070 };
static uint8_t ntp[FILE_BYTES];
static uint32_t cursor;
static unsigned files_opened,files_closed,chunks_read,allocations;
static int opened;
static size_t max_alloc,total_alloc;
void *pvPortMalloc(size_t n)
{
    if(n>max_alloc)max_alloc=n;
    total_alloc+=n;allocations++;
    return malloc(n);
}
void vPortFree(void *p){free(p);}
int disk_fs_request(fs_req_t *r)
{
    if(!r)return -1;
    switch(r->op){
    case FSOP_MOD_OPEN:
        if(!r->path || strcmp(r->path,"MUSIC/15K.NTP"))return -1;
        files_opened++;r->size=FILE_BYTES;cursor=0;opened=1;
        return 0;
    case FSOP_MOD_READ: {
        uint32_t bytes=FILE_BYTES-cursor;
        if(!opened)return -1;
        if(bytes>r->len)bytes=r->len;
        memcpy(r->buf,ntp+cursor,bytes);
        cursor+=bytes;r->out=bytes;chunks_read++;
        return 0;
    }
    case FSOP_MOD_CLOSE:files_closed++;opened=0;return 0;
    default:return -1;
    }
}
static void check(int yes,const char *msg)
{
    if(!yes){fprintf(stderr,"FAIL P2AA runtime: %s\n",msg);exit(1);}
}
static void fixture(void)
{
    memset(ntp,0,sizeof ntp);
    memcpy(ntp,"nfc!",4);
    ntp[4]=2;ntp[5]=4;ntp[6]=1;ntp[7]=1;ntp[8]=1;
    ntp[9]=4;memcpy(ntp+10,"test",4);
    const uint8_t tracks[12]={1,0,0x80, 0,0,2, 0,0,4, 1,0,6};
    memcpy(ntp+TRACK_OFF,tracks,sizeof tracks);
    ntp[INST_OFF]=4;ntp[INST_OFF+2]=1; // 256 bytes, type one-shot
    ntp[INST_OFF+10]=64;ntp[INST_OFF+14]=4;
    memcpy(ntp+INST_OFF+15,"tone",4);
    ntp[ORDER_OFF]=0;ntp[PAT_OFF]=25;ntp[PAT_OFF+1]=1;
    ntp[PAT_OFF+2]=4;ntp[PAT_OFF+3]=0x47;
    for(unsigned i=0;i<256;i++)
        ntp[PCM_OFF+i]=(uint8_t)(i+1);
}
int main(void)
{
    char path[SENSEI_PATH_CAP];
    sensei_runtime_module_t song;
    fixture();
    check(!sensei_runtime_choose("../TEST.NTP"),"traversal allowed");
    check(!sensei_runtime_choose("MUSIC/15K.MOD"),"legacy MOD accepted");
    check(!sensei_runtime_choose("MUSIC/15K.NPX"),"unknown extension accepted");
    check(sensei_runtime_choose("MUSIC/15K.NTP"),"native NTP rejected");
    check(sensei_runtime_pending(path,sizeof path),"pending selector missing");
    check(strcmp(path,"MUSIC/15K.NTP")==0,"selected path changed");
    check(!sensei_runtime_pending(path,sizeof path),"selected twice");
    check(sensei_runtime_load(path,&song),"native v2 load failed");
    check(song.file_size==FILE_BYTES && song.pcm_length==256u,
          "wrong file/PCM size");
    check(song.ntp_raw_patterns==song.file+PAT_OFF &&
          song.ntp_raw_patterns[0]==25u &&
          song.ntp_raw_patterns[1]==1u,
          "not pointing to original raw-score NTP bytes");
    check(song.order_count==1u && song.ntp_pattern_count==1u &&
          song.catalog[11]==64u,"wrong native instrument metadata");
    check(memcmp(song.pcm,ntp+PCM_OFF,256)==0,"DOC PCM transformed");
    check(allocations==2u && max_alloc==FILE_BYTES &&
          total_alloc==(FILE_BYTES+256u),
          "duplicate NTP pattern allocation or excess heap retained");
    check(files_opened==1u && files_closed==1u && chunks_read==1u,
          "FAT request lifecycle");
    check(sensei_runtime_status()==SENSEI_RT_READY_PCM,
          "claimed playing before DMA");
    sensei_runtime_free(&song);
    check(song.file==NULL && song.pcm==NULL,"memory not freed");
    puts("PASS P2AA: FAT picker -> original NTP -> byte-exact DOC PCM");
    puts("PASS P2AA: exactly TWO allocations, no ProTracker shadow pattern");
    puts("PASS P2AA: obsolete MOD extension rejected without FAT access");
    return 0;
}
