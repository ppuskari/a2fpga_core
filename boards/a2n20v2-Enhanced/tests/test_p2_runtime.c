/* End-to-end P2 runtime filesystem test with synthetic MOD.
 * Actual MCU FatFS logic is tested separately in native builds; this
 * exercises the real production selector, broker call order and decoder.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "disk.h"
#include "sensei_runtime.h"

static uint8_t synthetic[1084+1024+256];
static uint32_t cursor;
static unsigned files_opened,files_closed,chunks_read;
static int opened;

void *pvPortMalloc(size_t n){return malloc(n);}
void vPortFree(void *p){free(p);}

int disk_fs_request(fs_req_t *r)
{
    if(!r)return -1;
    switch(r->op) {
    case FSOP_MOD_OPEN:
        if(!r->path || strcmp(r->path,"MUSIC/BOOGIE.MOD"))return -1;
        files_opened++;
        r->size=sizeof synthetic;
        cursor=0;opened=1;
        return 0;
    case FSOP_MOD_READ: {
        uint32_t bytes=(uint32_t)(sizeof synthetic)-cursor;
        if(!opened)return -1;
        if(bytes>r->len)bytes=r->len;
        memcpy(r->buf,synthetic+cursor,bytes);
        cursor+=bytes;r->out=bytes;chunks_read++;
        return 0;
    }
    case FSOP_MOD_CLOSE:
        files_closed++;opened=0;return 0;
    default:return -1;
    }
}
static void must(int cond,const char *why)
{
    if(!cond){fprintf(stderr,"FAIL P2 runtime: %s\n",why);exit(1);}
}
int main(void)
{
    char path[SENSEI_PATH_CAP];
    sensei_runtime_module_t song;
    memset(synthetic,0,sizeof synthetic);
    memcpy(synthetic+1080,"M.K.",4);
    synthetic[950]=1;
    synthetic[20+23]=128;synthetic[20+25]=48;
    synthetic[20+29]=128;
    for(unsigned i=0;i<256;i++)
        synthetic[1084+1024+i]=(uint8_t)(i^0x40);
    must(!sensei_runtime_choose("../BOOGIE.MOD"),"directory traversal allowed");
    must(!sensei_runtime_choose("MOVIES/CLIP.AVI"),"wrong extension allowed");
    must(sensei_runtime_choose("MUSIC/BOOGIE.MOD"),"file picker selection");
    must(sensei_runtime_pending(path,sizeof path),"missing queued file");
    must(strcmp(path,"MUSIC/BOOGIE.MOD")==0,"path not preserved");
    must(!sensei_runtime_pending(path,sizeof path),"selection consumed twice");
    must(sensei_runtime_load(path,&song),"synthetic MOD decode failed");
    must(song.file_size==sizeof synthetic && song.pcm_length==256,
         "unexpected raw file size or DOC sample bytes");
    must(song.song.count==0 && song.song.rows!=NULL,
         "runtime player must not silently treat raw patterns as flattened rows");
    must(song.order_count==1 && song.catalog[7]==48,
         "runtime sample catalog not decoded");
    must(files_opened==1 && files_closed==1 && chunks_read==1,
         "FAT broker open/read/close mismatch");
    must(sensei_runtime_status()==SENSEI_RT_READY_PCM,
         "runtime status should not claim PLAYING before DOC upload");
    sensei_runtime_free(&song);
    must(!song.file && !song.pcm,"buffers were not released");
    puts("PASS P2 runtime: folder picker -> FatFS broker -> original MOD -> DOC PCM");
    puts("PASS P2 runtime: no song precomputation; playback remains gated on PCM DMA");
    return 0;
}
