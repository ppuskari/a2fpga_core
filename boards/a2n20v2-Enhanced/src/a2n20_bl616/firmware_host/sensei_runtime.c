/*
 * P2AA NTP-only runtime: immutable FAT source, no MOD fallback/translation.
 * Disk requests run through the disk task. Only Sensei worker may call load.
 * Parse scratch is BSS to keep the BL616 4KB worker stack bounded.
 */
#include "sensei_runtime.h"
#include "sensei_ntp_import.h"
#include "disk.h"
#include "FreeRTOS.h"
#include <ctype.h>
#include <string.h>

static volatile uint32_t g_path_seq;
static char g_path[SENSEI_PATH_CAP];
static uint32_t g_consumed_seq;
static volatile sensei_runtime_status_t g_status=SENSEI_RT_IDLE;
static volatile uint32_t g_stop_request,g_audition_mode;

static bool ntp_path_ok(const char *path)
{
    size_t n;
    if(!path)return false;
    n=strlen(path);
    if(n<5u || n>=SENSEI_PATH_CAP || strstr(path,"..") ||
       path[0]=='/' || strchr(path,':') || strchr(path,'\\'))
        return false;
    return path[n-4]=='.' &&
           tolower((unsigned char)path[n-3])=='n' &&
           tolower((unsigned char)path[n-2])=='t' &&
           tolower((unsigned char)path[n-1])=='p';
}
bool sensei_runtime_choose(const char *path)
{
    if(!ntp_path_ok(path))return false;
    __atomic_add_fetch(&g_path_seq,1u,__ATOMIC_RELEASE);
    memcpy(g_path,path,strlen(path)+1u);
    __atomic_add_fetch(&g_path_seq,1u,__ATOMIC_RELEASE);
    g_status=SENSEI_RT_SELECTED;
    return true;
}
bool sensei_runtime_pending(char *dst,size_t cap)
{
    uint32_t first,last;
    if(!dst||cap<SENSEI_PATH_CAP)return false;
    first=__atomic_load_n(&g_path_seq,__ATOMIC_ACQUIRE);
    if(!first||(first&1u)||first==g_consumed_seq)return false;
    memcpy(dst,g_path,SENSEI_PATH_CAP);
    last=__atomic_load_n(&g_path_seq,__ATOMIC_ACQUIRE);
    if(first!=last||(last&1u))return false;
    g_consumed_seq=last;
    return true;
}
sensei_runtime_status_t sensei_runtime_status(void){return g_status;}
void sensei_runtime_set_status(sensei_runtime_status_t s){g_status=s;}
void sensei_runtime_set_audition_mode(uint8_t mode)
{
    if(mode<=6u)__atomic_store_n(&g_audition_mode,mode,__ATOMIC_RELEASE);
}
uint8_t sensei_runtime_audition_mode(void)
{
    return (uint8_t)__atomic_load_n(&g_audition_mode,__ATOMIC_ACQUIRE);
}
void sensei_runtime_request_stop(void)
{
    __atomic_store_n(&g_stop_request,1u,__ATOMIC_RELEASE);
}
bool sensei_runtime_take_stop_request(void)
{
    return __atomic_exchange_n(&g_stop_request,0u,__ATOMIC_ACQ_REL)!=0u;
}
void sensei_runtime_free(sensei_runtime_module_t *m)
{
    if(!m)return;
    if(m->file)vPortFree(m->file);
    if(m->pcm)vPortFree(m->pcm);
    memset(m,0,sizeof(*m));
}
bool sensei_runtime_load(const char *path,sensei_runtime_module_t *m)
{
    fs_req_t req;
    static sensei_ntp_decoded_t ntp; /* single worker, non-reentrant */
    uint32_t remaining=0u,done=0u;
    bool ok=false;
    if(!m||!ntp_path_ok(path))return false;
    memset(m,0,sizeof(*m));
    g_status=SENSEI_RT_LOADING;
    memset(&req,0,sizeof(req));
    req.op=FSOP_MOD_OPEN; /* legacy disk broker opcode, also reads NTP */
    req.path=path;
    if(disk_fs_request(&req)!=0 || req.size<13u ||
       req.size>SENSEI_RUNTIME_MAX_FILE)goto finish;
    m->file_size=req.size;
    m->file=(uint8_t*)pvPortMalloc(req.size);
    if(!m->file)goto finish;
    remaining=req.size;
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
    /* First pass validates all score/instrument fields and samples.
     * Second pass copies only DOC PCM; never creates P2U pattern bytes. */
    if(!sensei_ntp_import(m->file,m->file_size,NULL,0,&ntp) ||
       !ntp.pcm_bytes || ntp.pcm_bytes>65536u ||
       !ntp.pattern_bytes)goto finish;
    m->pcm=(uint8_t*)pvPortMalloc(ntp.pcm_bytes);
    if(!m->pcm)goto finish;
    if(!sensei_ntp_import(m->file,m->file_size,m->pcm,ntp.pcm_bytes,&ntp))
        goto finish;
    memcpy(m->catalog,ntp.catalog,sizeof(m->catalog));
    memcpy(m->order_table,ntp.orders,sizeof(m->order_table));
    memcpy(m->channel_pan,ntp.channel_pan,sizeof(m->channel_pan));
    memcpy(m->ntp_instrument_map,ntp.instrument_map,
           sizeof(m->ntp_instrument_map));
    memcpy(m->ntp_irq_instruments,ntp.irq_instruments,
           sizeof(m->ntp_irq_instruments));
    m->ntp_raw_patterns=m->file+ntp.pattern_offset;
    m->ntp_pattern_count=ntp.pattern_count;
    m->ntp_version=ntp.ntp_version;
    m->order_count=ntp.order_count;
    m->pcm_length=ntp.pcm_bytes;
    m->ntp_nonideal=ntp.nonideal_pairs;
    ok=true;
finish:
    memset(&req,0,sizeof(req));
    req.op=FSOP_MOD_CLOSE;
    (void)disk_fs_request(&req);
    if(!ok)sensei_runtime_free(m);
    g_status=ok?SENSEI_RT_READY_PCM:SENSEI_RT_ERROR;
    return ok;
}
