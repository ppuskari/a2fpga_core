/*
 * Runtime MOD selector + loader for SenseiPlay8 on the BL616.
 * Files come from the existing USB/SD FAT volume through the disk-thread
 * broker. No platform preconversion, private generated header, or compiled
 * song selection IDs.
 *
 * IMPORTANT: loading/decoding PCM does not transfer the waveform bank to
 * DOC RAM. Until the dedicated MCU->DOC upload path is implemented, no
 * runtime song may transition into PLAYING.
 */
#include "sensei_runtime.h"
#include "sensei_mod_decode.h"
#include "disk.h"
#include "FreeRTOS.h"
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

static volatile uint32_t g_path_seq;
static char g_path[SENSEI_PATH_CAP];
static uint32_t g_consumed_seq;
static volatile sensei_runtime_status_t g_status=SENSEI_RT_IDLE;
static volatile uint32_t g_stop_request;
static volatile uint8_t g_audition_mode;


static bool mod_path_ok(const char *path)
{
    size_t n;
    if (!path)return false;
    n=strlen(path);
    if (n<5 || n>=SENSEI_PATH_CAP || strstr(path,"..") ||
        path[0]=='/' || strchr(path,':') || strchr(path,'\\'))
        return false;
    return path[n-4]=='.' &&
        tolower((unsigned char)path[n-3])=='m' &&
        tolower((unsigned char)path[n-2])=='o' &&
        tolower((unsigned char)path[n-1])=='d';
}

bool sensei_runtime_choose(const char *relative_path)
{
    size_t n;
    if (!mod_path_ok(relative_path))return false;
    n=strlen(relative_path)+1u;
    __atomic_add_fetch(&g_path_seq,1u,__ATOMIC_RELEASE); /* odd = writer */
    memcpy(g_path,relative_path,n);
    __atomic_add_fetch(&g_path_seq,1u,__ATOMIC_RELEASE); /* even = ready */
    g_status=SENSEI_RT_SELECTED;
    return true;
}
bool sensei_runtime_pending(char *dst,size_t cap)
{
    uint32_t first,last;
    if(!dst || cap<SENSEI_PATH_CAP)return false;
    first=__atomic_load_n(&g_path_seq,__ATOMIC_ACQUIRE);
    if(!first || (first&1u) || first==g_consumed_seq)return false;
    memcpy(dst,g_path,SENSEI_PATH_CAP);
    last=__atomic_load_n(&g_path_seq,__ATOMIC_ACQUIRE);
    if(first!=last || (last&1u))return false;
    g_consumed_seq=last;
    return true;
}

sensei_runtime_status_t sensei_runtime_status(void)
{
    return g_status;
}
void sensei_runtime_set_status(sensei_runtime_status_t value)
{
    g_status=value;
}
void sensei_runtime_set_audition_mode(uint8_t mode)
{
    if(mode<=6u)
        __atomic_store_n(&g_audition_mode,mode,__ATOMIC_RELEASE);
}
uint8_t sensei_runtime_audition_mode(void)
{
    return __atomic_load_n(&g_audition_mode,__ATOMIC_ACQUIRE);
}
void sensei_runtime_request_stop(void)
{
    __atomic_store_n(&g_stop_request,1u,__ATOMIC_RELEASE);
}
bool sensei_runtime_take_stop_request(void)
{
    return __atomic_exchange_n(&g_stop_request,0u,__ATOMIC_ACQ_REL)!=0;
}
void sensei_runtime_free(sensei_runtime_module_t *m)
{
    if(!m)return;
    if(m->file)vPortFree(m->file);
    if(m->pcm)vPortFree(m->pcm);
    memset(m,0,sizeof(*m));
}
bool sensei_runtime_load(const char *relative_path,sensei_runtime_module_t *m)
{
    fs_req_t req;
    sensei_mod_decoded_t d;
    uint32_t remaining,done;
    bool ok=false;
    if (!m || !mod_path_ok(relative_path))return false;
    memset(m,0,sizeof(*m));
    g_status=SENSEI_RT_LOADING;
    memset(&req,0,sizeof(req));
    req.op=FSOP_MOD_OPEN;
    req.path=relative_path;
    if(disk_fs_request(&req)!=0 || req.size<1084u ||
       req.size>SENSEI_RUNTIME_MAX_FILE)
        goto finish;
    m->file_size=req.size;
    m->file=(uint8_t*)pvPortMalloc(req.size);
    if(!m->file)goto finish;
    remaining=req.size;
    done=0;
    while(remaining) {
        memset(&req,0,sizeof(req));
        req.op=FSOP_MOD_READ;
        req.buf=m->file+done;
        req.len=remaining>4096u?4096u:remaining;
        if(disk_fs_request(&req)!=0 || !req.out || req.out>req.len)
            goto finish;
        remaining-=req.out;
        done+=req.out;
    }
    // First parse without PCM writes to calculate exact aligned DOC
    // instrument memory. Do not reserve 48 KiB for every short song.
    if(!sensei_mod_decode(m->file,m->file_size,NULL,0,&d) ||
       !d.doc_pcm_bytes || d.doc_pcm_bytes>SENSEI_RUNTIME_MAX_SAMPLE_BANK)
        goto finish;
    m->pcm=(uint8_t*)pvPortMalloc(d.doc_pcm_bytes);
    if(!m->pcm)goto finish;
    if(!sensei_mod_decode(m->file,m->file_size,
                          m->pcm,d.doc_pcm_bytes,&d))
        goto finish;
    memcpy(m->catalog,d.catalog,sizeof(m->catalog));
    memcpy(m->order_table,d.orders,sizeof(m->order_table));
    m->order_count=d.order_count;
    m->pcm_length=d.doc_pcm_bytes;
    m->song.rows=m->file+d.pattern_offset; /* raw patterns, not flattened */
    m->song.catalog=m->catalog;
    m->song.count=0; /* runtime mode does NOT use flattened row count */
    ok=true;
finish:
    memset(&req,0,sizeof(req));
    req.op=FSOP_MOD_CLOSE;
    disk_fs_request(&req);
    if(!ok)sensei_runtime_free(m);
    g_status=ok?SENSEI_RT_READY_PCM:SENSEI_RT_ERROR;
    return ok;
}
