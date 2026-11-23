/* BL616 FAT .MOD jukebox catalog.
 * Walk only from the MOD PCM thread; filesystem access stays serialized in
 * disk.c using a private DIR, so FTP LIST and MOD read handles are preserved.
 * Paths are root-relative. Filenames and subdirectories are sorted globally
 * (case-insensitive) for deterministic NEXT/PREVIOUS behavior.
 */
#include "mcu_mod_jukebox.h"
#include "mod_filename.h"
#include "disk.h"
#include "osd_console.h"
#include "FreeRTOS.h"
#include "task.h"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define JUKE_DIR_LIMIT 96u
/* 500 individual malloc() allocations were costly and fragmented the same
 * libc heap as the M2 Apple browser. Pack full track paths into 2K blocks;
 * only one allocation per block, each pointer remains valid through sorting,
 * Next/Previous and playlist playback. Oversized libraries return an explicit
 * recoverable error, never FreeRTOS' fatal malloc hook. */
#define JUKE_TRACK_CHUNK_BYTES 2048u
#define JUKE_TRACK_CHUNK_LIMIT 36u
static char *s_tracks[MOD_JUKE_MAX_TRACKS];
static char *s_track_chunks[JUKE_TRACK_CHUNK_LIMIT];
static unsigned s_track_chunk_count,s_track_chunk_used;
static unsigned s_count;
static bool s_truncated,s_last_error;

static int icmp(const char *a, const char *b)
{
    while (*a && *b) {
        int x=tolower((unsigned char)*a++);
        int y=tolower((unsigned char)*b++);
        if(x!=y) return x-y;
    }
    return (unsigned char)*a-(unsigned char)*b;
}
static int track_cmp(const void *a,const void *b)
{
    const char *const *x=(const char *const *)a;
    const char *const *y=(const char *const *)b;
    return icmp(*x,*y);
}
/* SDK heap_3 implements pvPortMalloc with libc malloc and a suspended
 * scheduler. But if malloc returns NULL, pvPortMalloc invokes the global
 * fatal hook which DISABLES INTERRUPTS, freezing USB HID and the mailbox.
 * A 506-file jukebox plus the resident M2 Apple catalog can run low on
 * heap. Use identical scheduler serialization, but handle libc OOM
 * locally so the scan reports failure instead of halting the whole MCU. */
static void *juke_try_alloc(size_t n)
{
    vTaskSuspendAll();
    void *p=malloc(n);
    (void)xTaskResumeAll();
    return p;
}
static char *juke_strdup(const char *s)
{
    size_t n=strlen(s)+1u;
    char *p=(char *)juke_try_alloc(n);
    if(p)memcpy(p,s,n);
    return p;
}
static char *juke_track_store(const char *path)
{
    const size_t n=strlen(path)+1u;
    if(n>JUKE_TRACK_CHUNK_BYTES)return NULL;
    if(s_track_chunk_count==0u ||
       s_track_chunk_used+n>JUKE_TRACK_CHUNK_BYTES) {
        if(s_track_chunk_count>=JUKE_TRACK_CHUNK_LIMIT)return NULL;
        char *chunk=(char *)juke_try_alloc(JUKE_TRACK_CHUNK_BYTES);
        if(!chunk)return NULL;
        s_track_chunks[s_track_chunk_count++]=chunk;
        s_track_chunk_used=0u;
    }
    char *p=s_track_chunks[s_track_chunk_count-1u]+s_track_chunk_used;
    memcpy(p,path,n);
    s_track_chunk_used+=(unsigned)n;
    return p;
}
static void juke_free(char *p)
{
    if(!p)return;
    vTaskSuspendAll();
    free(p);
    (void)xTaskResumeAll();
}
static bool safe_dir(const char *path)
{
    if(!path || strlen(path)>=MOD_JUKE_PATH_CAP || strstr(path,"..") ||
       path[0]=='/' || strchr(path,':') || strchr(path,'\\'))
        return false;
    return true;
}
void mod_jukebox_clear(void)
{
    for(unsigned i=0;i<s_track_chunk_count;i++) {
        juke_free(s_track_chunks[i]);
        s_track_chunks[i]=NULL;
    }
    s_track_chunk_count=0u;
    s_track_chunk_used=0u;
    for(unsigned i=0;i<s_count;i++)s_tracks[i]=NULL;
    s_count=0;
    s_truncated=false;
    s_last_error=false;
}
unsigned mod_jukebox_count(void){return s_count;}
const char *mod_jukebox_track(unsigned index)
{
    return index<s_count?s_tracks[index]:NULL;
}
int mod_jukebox_find(const char *relative_file)
{
    if(!relative_file || !relative_file[0])
        return -1;
    for(unsigned i=0;i<s_count;i++)
        if(s_tracks[i] && icmp(s_tracks[i],relative_file)==0)
            return (int)i;
    return -1;
}
bool mod_jukebox_truncated(void){return s_truncated;}
bool mod_jukebox_last_error(void){return s_last_error;}

bool mod_jukebox_scan(const char *root,bool recursive)
{
    char *dirs[JUKE_DIR_LIMIT]={0};
    unsigned head=0,tail=0;
    bool failed=false;
    unsigned entries=0,nonmod=0,dir_entries=0,longpath=0;
    if(!safe_dir(root)) {
        s_last_error=true;
        osd_log("MCU JUKE: INVALID DIRECTORY PATH");
        return false;
    }
    mod_jukebox_clear();
    dirs[tail]=juke_strdup(root);
    if(!dirs[tail]) {
        s_last_error=true;
        osd_log("MCU JUKE: LOW HEAP BEFORE DIR OPEN");
        return false;
    }
    tail++;
    while(head<tail && !failed) {
        fs_req_t r;
        bool opened=false;
        memset(&r,0,sizeof(r));
        r.op=FSOP_MOD_LIST_OPEN;
        r.path=dirs[head];
        const int open_fr=disk_fs_request(&r);
        if(open_fr!=0) {
            osd_log("MCU JUKE: DIR OPEN FAIL FR=%d /%s",
                    open_fr,dirs[head]);
            failed=true;
        }else{
            opened=true;
            for(;;) {
                char path[MOD_JUKE_PATH_CAP];
                int n;
                memset(&r,0,sizeof(r));
                r.op=FSOP_MOD_LIST_NEXT;
                const int read_fr=disk_fs_request(&r);
                if(read_fr!=0) {
                    osd_log("MCU JUKE: DIR READ FAIL FR=%d AFTER %u ENTRIES",
                            read_fr,entries);
                    failed=true;
                    break;
                }
                if(!r.name[0])break;
                if(!strcmp(r.name,".") || !strcmp(r.name,".."))continue;
                ++entries;
                n=dirs[head][0] ?
                    snprintf(path,sizeof(path),"%s/%s",dirs[head],r.name):
                    snprintf(path,sizeof(path),"%s",r.name);
                if(n<0 || (unsigned)n>=sizeof(path)) {
                    s_truncated=true;
                    ++longpath;
                    continue;
                }
                if(r.attr & 0x10u) {  /* FatFS AM_DIR */
                    ++dir_entries;
                    if(recursive) {
                        if(tail<JUKE_DIR_LIMIT) {
                            dirs[tail]=juke_strdup(path);
                            if(!dirs[tail]) {
                                osd_log("MCU JUKE: LOW HEAP FOR SUBDIR AFTER %u",
                                        entries);
                                failed=true;break;
                            }
                            tail++;
                        }else s_truncated=true;
                    }
                }else if(mod_filename_matches(r.name)) {
                    if(s_count<MOD_JUKE_MAX_TRACKS) {
                        s_tracks[s_count]=juke_track_store(path);
                        if(!s_tracks[s_count]) {
                            osd_log("MCU JUKE: LOW HEAP FOR TRACK %u (CHUNKS=%u)",
                                    s_count,s_track_chunk_count);
                            failed=true;break;
                        }
                        s_count++;
                    }else s_truncated=true;
                }else ++nonmod;
            }
        }
        if(opened) {
            memset(&r,0,sizeof(r));
            r.op=FSOP_MOD_LIST_CLOSE;
            const int close_fr=disk_fs_request(&r);
            if(close_fr!=0) {
                osd_log("MCU JUKE: DIR CLOSE FAIL FR=%d AFTER %u ENTRIES",
                        close_fr,entries);
                failed=true;
            }
        }
        juke_free(dirs[head]);
        dirs[head]=NULL;
        head++;
    }
    for(;head<tail;head++)if(dirs[head])juke_free(dirs[head]);
    if(failed) {
        osd_log("MCU JUKE: DIRECTORY SCAN FAILED AFTER %u ENTRIES / %u TRACKS",
                entries,s_count);
        mod_jukebox_clear();
        s_last_error=true; /* distinct from successfully scanned empty folder */
        return false;
    }
    if(s_count)qsort(s_tracks,s_count,sizeof(s_tracks[0]),track_cmp);
    osd_log("MCU JUKE: %u MODS %s%s CHUNKS=%u",s_count,
            recursive?"TREE":"FOLDER",s_truncated?" (LIMIT)":"",
            s_track_chunk_count);
    osd_log("MCU JUKE: SEEN %u NONMOD %u DIR %u PATHLONG %u",
            entries,nonmod,dir_entries,longpath);
    return s_count!=0;
}
