/* BL616 FAT .MOD jukebox catalog.
 * The MOD PCM thread is the exclusive owner of scans, sorting and playback
 * pathname reconstruction. All directory operations use the disk FS broker.
 *
 * M3 heap fix: keep each directory prefix ONCE and store only its filenames.
 * A 500-track folder no longer allocates 500 duplicated copies of its path.
 * Sorted entries have compact 4-byte indices into 1-KiB filename chunks.
 * The playlist stays independent from the resident M2 Apple browser catalog.
 */
#include "mcu_mod_jukebox.h"
#include "mod_filename.h"
#include "disk.h"
#include "osd_console.h"
#include "FreeRTOS.h"
#include "task.h"
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define JUKE_DIR_LIMIT 96u
/* With the smallest 256-byte fallback and maximum 128-byte basename,
 * each chunk still holds >=2 tracks. 256 slots cover all 512 entries;
 * chunk_id stays uint8_t (0..255). Normal scans use ~7 chunks for 500
 * 12-character filenames, not 256. */
#define JUKE_TRACK_CHUNK_BYTES 1024u
#define JUKE_TRACK_CHUNK_LIMIT 256u
#define JUKE_TRACK_MIN_CHUNK 256u

typedef struct {
    uint16_t offset;
    uint8_t chunk_id;
    uint8_t dir_id;
} juke_track_t;

static juke_track_t s_tracks[MOD_JUKE_MAX_TRACKS];
static char *s_dirs[JUKE_DIR_LIMIT]; /* interned full relative directory paths */
static char *s_track_chunks[JUKE_TRACK_CHUNK_LIMIT];
static unsigned s_dir_count,s_track_chunk_count,s_track_chunk_used;
static unsigned s_track_chunk_capacity,s_track_alloc_bytes,s_name_bytes;
static unsigned s_dir_alloc_bytes,s_chunk_fallbacks;
static unsigned s_count;
static bool s_truncated,s_last_error,s_chunk_limit_error;
/* mod_jukebox_track() is called ONLY from the MOD PCM thread. The returned
 * string is transient until the next call, as start_song() immediately
 * copies the full path into its stable request and now-playing buffers. */
static char s_path_scratch[MOD_JUKE_PATH_CAP];

static int icmp(const char *a, const char *b)
{
    while (*a && *b) {
        int x=tolower((unsigned char)*a++);
        int y=tolower((unsigned char)*b++);
        if(x!=y)return x-y;
    }
    return (unsigned char)*a-(unsigned char)*b;
}

/* The shared FreeRTOS heap_3 wraps libc malloc under a scheduler lock, but
 * the pvPortMalloc failure hook is fatal to USB HID/audio. Bypass only the
 * fatal hook; keep the SAME scheduler serialization for each allocation. */
static void *juke_try_alloc(size_t n)
{
    vTaskSuspendAll();
    void *p=malloc(n);
    (void)xTaskResumeAll();
    return p;
}
static void juke_free(char *p)
{
    if(!p)return;
    vTaskSuspendAll();
    free(p);
    (void)xTaskResumeAll();
}
static char *juke_strdup(const char *s)
{
    const size_t n=strlen(s)+1u;
    char *p=(char *)juke_try_alloc(n);
    if(p) {
        memcpy(p,s,n);
        s_dir_alloc_bytes+=(unsigned)n;
    }
    return p;
}
static const char *track_name(const juke_track_t *t)
{
    return s_track_chunks[t->chunk_id]+t->offset;
}
static bool track_path(const juke_track_t *t,char dst[MOD_JUKE_PATH_CAP])
{
    const char *dir=s_dirs[t->dir_id];
    const char *name=track_name(t);
    if(!dir || !name)return false;
    const int n=dir[0] ?
        snprintf(dst,MOD_JUKE_PATH_CAP,"%s/%s",dir,name):
        snprintf(dst,MOD_JUKE_PATH_CAP,"%s",name);
    return n>=0 && (unsigned)n<MOD_JUKE_PATH_CAP;
}
static int track_cmp(const void *a,const void *b)
{
    char left[MOD_JUKE_PATH_CAP],right[MOD_JUKE_PATH_CAP];
    const juke_track_t *x=(const juke_track_t *)a;
    const juke_track_t *y=(const juke_track_t *)b;
    (void)track_path(x,left); /* scan already checked path capacity */
    (void)track_path(y,right);
    return icmp(left,right);
}
/* Allocate names only, NEVER the repeated full "dir/filename" path.
 * Use 1KiB chunks for low fragmentation and permit 512/256-byte fallback
 * when the largest contiguous heap block has become too small. */
static bool juke_track_store(const char *name,unsigned dir_id)
{
    const size_t n=strlen(name)+1u;
    if(!n || n>JUKE_TRACK_CHUNK_BYTES || dir_id>=s_dir_count ||
       s_count>=MOD_JUKE_MAX_TRACKS)return false;
    if(!s_track_chunk_count || s_track_chunk_used+n>s_track_chunk_capacity) {
        if(s_track_chunk_count>=JUKE_TRACK_CHUNK_LIMIT) {
            s_chunk_limit_error=true;
            return false;
        }
        char *chunk=NULL;
        unsigned capacity=JUKE_TRACK_CHUNK_BYTES;
        while(capacity>=JUKE_TRACK_MIN_CHUNK && capacity>=n) {
            chunk=(char *)juke_try_alloc(capacity);
            if(chunk)break;
            capacity>>=1;
        }
        if(!chunk)return false;
        if(capacity!=JUKE_TRACK_CHUNK_BYTES)s_chunk_fallbacks++;
        s_track_chunks[s_track_chunk_count++]=chunk;
        s_track_chunk_capacity=capacity;
        s_track_chunk_used=0u;
        s_track_alloc_bytes+=capacity;
    }
    juke_track_t *t=&s_tracks[s_count];
    t->chunk_id=(uint8_t)(s_track_chunk_count-1u);
    t->dir_id=(uint8_t)dir_id;
    t->offset=(uint16_t)s_track_chunk_used;
    memcpy(s_track_chunks[t->chunk_id]+t->offset,name,n);
    s_track_chunk_used+=(unsigned)n;
    s_name_bytes+=(unsigned)n;
    return true;
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
    for(unsigned i=0;i<s_dir_count;i++) {
        juke_free(s_dirs[i]);
        s_dirs[i]=NULL;
    }
    s_dir_count=s_track_chunk_count=s_track_chunk_used=0u;
    s_track_chunk_capacity=s_track_alloc_bytes=s_name_bytes=0u;
    s_dir_alloc_bytes=s_chunk_fallbacks=0u;
    s_count=0u;
    s_truncated=s_last_error=s_chunk_limit_error=false;
    s_path_scratch[0]=0;
}
unsigned mod_jukebox_count(void){return s_count;}
const char *mod_jukebox_track(unsigned index)
{
    if(index>=s_count || !track_path(&s_tracks[index],s_path_scratch))
        return NULL;
    return s_path_scratch;
}
int mod_jukebox_find(const char *relative_file)
{
    if(!relative_file || !relative_file[0])return -1;
    char path[MOD_JUKE_PATH_CAP];
    for(unsigned i=0;i<s_count;i++)
        if(track_path(&s_tracks[i],path) && icmp(path,relative_file)==0)
            return (int)i;
    return -1;
}
bool mod_jukebox_truncated(void){return s_truncated;}
bool mod_jukebox_last_error(void){return s_last_error;}

bool mod_jukebox_scan(const char *root,bool recursive)
{
    unsigned head=0,tail=0;
    bool failed=false;
    unsigned entries=0,nonmod=0,dir_entries=0,longpath=0;
    if(!safe_dir(root)) {
        s_last_error=true;
        osd_log("MCU JUKE: INVALID DIRECTORY PATH");
        return false;
    }
    mod_jukebox_clear();
    s_dirs[tail]=juke_strdup(root);
    if(!s_dirs[tail]) {
        s_last_error=true;
        osd_log("MCU JUKE: LOW HEAP BEFORE DIR OPEN");
        return false;
    }
    ++tail;
    s_dir_count=tail;
    while(head<tail && !failed) {
        fs_req_t r;
        bool opened=false;
        memset(&r,0,sizeof(r));
        r.op=FSOP_MOD_LIST_OPEN;
        r.path=s_dirs[head];
        const int open_fr=disk_fs_request(&r);
        if(open_fr!=0) {
            osd_log("MCU JUKE: DIR OPEN FAIL FR=%d /%s",open_fr,s_dirs[head]);
            failed=true;
        } else {
            opened=true;
            for(;;) {
                char path[MOD_JUKE_PATH_CAP];
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
                const int n=s_dirs[head][0] ?
                    snprintf(path,sizeof(path),"%s/%s",s_dirs[head],r.name):
                    snprintf(path,sizeof(path),"%s",r.name);
                if(n<0 || (unsigned)n>=sizeof(path)) {
                    s_truncated=true;
                    ++longpath;
                    continue;
                }
                if(r.attr & 0x10u) { /* FatFS AM_DIR */
                    ++dir_entries;
                    if(recursive) {
                        if(tail<JUKE_DIR_LIMIT) {
                            s_dirs[tail]=juke_strdup(path);
                            if(!s_dirs[tail]) {
                                osd_log("MCU JUKE: LOW HEAP FOR DIR AFTER %u",entries);
                                failed=true;
                                break;
                            }
                            ++tail;
                            s_dir_count=tail;
                        } else s_truncated=true;
                    }
                } else if(mod_filename_matches(r.name)) {
                    if(s_count<MOD_JUKE_MAX_TRACKS) {
                        if(!juke_track_store(r.name,head)) {
                            osd_log("MCU JUKE: %s TRACK %u CHUNKS=%u NEED=%u",
                                    s_chunk_limit_error?"CHUNK LIMIT":"LOW HEAP",
                                    s_count,s_track_chunk_count,
                                    (unsigned)(strlen(r.name)+1u));
                            failed=true;
                            break;
                        }
                        ++s_count;
                    } else s_truncated=true;
                } else ++nonmod;
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
        ++head; /* keep directories resident for subsequent playback */
    }
    if(failed) {
        osd_log("MCU JUKE: SCAN FAILED ENTRIES=%u TRACKS=%u CHUNKS=%u",
                entries,s_count,s_track_chunk_count);
        osd_log("MCU JUKE: FAIL MEM=%uB NAMES=%uB DIRBYTES=%uB FALLBACK=%u",
                s_track_alloc_bytes,s_name_bytes,s_dir_alloc_bytes,
                s_chunk_fallbacks);
        mod_jukebox_clear();
        s_last_error=true;
        return false;
    }
    if(s_count>1u)qsort(s_tracks,s_count,sizeof(s_tracks[0]),track_cmp);
    osd_log("MCU JUKE: %u MODS %s%s CHUNKS=%u ALLOC=%uB NAMES=%uB",
            s_count,recursive?"TREE":"FOLDER",
            s_truncated?" (LIMIT)":"",
            s_track_chunk_count,s_track_alloc_bytes,s_name_bytes);
    osd_log("MCU JUKE: DIRS=%u DIRBYTES=%uB FALLBACK=%u",
            s_dir_count,s_dir_alloc_bytes,s_chunk_fallbacks);
    osd_log("MCU JUKE: SEEN %u NONMOD %u DIR %u PATHLONG %u",
            entries,nonmod,dir_entries,longpath);
    return s_count!=0;
}
