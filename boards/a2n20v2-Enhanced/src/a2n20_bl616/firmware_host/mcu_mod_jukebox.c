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
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define JUKE_DIR_LIMIT 96u
static char *s_tracks[MOD_JUKE_MAX_TRACKS];
static unsigned s_count;
static bool s_truncated;

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
static char *juke_strdup(const char *s)
{
    size_t n=strlen(s)+1u;
    char *p=(char *)pvPortMalloc(n);
    if(p)memcpy(p,s,n);
    return p;
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
    for(unsigned i=0;i<s_count;i++) {
        vPortFree(s_tracks[i]);
        s_tracks[i]=NULL;
    }
    s_count=0;
    s_truncated=false;
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

bool mod_jukebox_scan(const char *root,bool recursive)
{
    char *dirs[JUKE_DIR_LIMIT]={0};
    unsigned head=0,tail=0;
    bool failed=false;
    unsigned entries=0,nonmod=0,dir_entries=0,longpath=0;
    if(!safe_dir(root))return false;
    mod_jukebox_clear();
    dirs[tail]=juke_strdup(root);
    if(!dirs[tail])return false;
    tail++;
    while(head<tail && !failed) {
        fs_req_t r;
        bool opened=false;
        memset(&r,0,sizeof(r));
        r.op=FSOP_MOD_LIST_OPEN;
        r.path=dirs[head];
        if(disk_fs_request(&r)!=0) {
            osd_log("MCU JUKE: CANNOT OPEN DIR %s",dirs[head]);
            failed=true;
        }else{
            opened=true;
            for(;;) {
                char path[MOD_JUKE_PATH_CAP];
                int n;
                memset(&r,0,sizeof(r));
                r.op=FSOP_MOD_LIST_NEXT;
                if(disk_fs_request(&r)!=0) {failed=true;break;}
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
                            if(!dirs[tail]) {failed=true;break;}
                            tail++;
                        }else s_truncated=true;
                    }
                }else if(mod_filename_matches(r.name)) {
                    if(s_count<MOD_JUKE_MAX_TRACKS) {
                        s_tracks[s_count]=juke_strdup(path);
                        if(!s_tracks[s_count]) {failed=true;break;}
                        s_count++;
                    }else s_truncated=true;
                }else ++nonmod;
            }
        }
        if(opened) {
            memset(&r,0,sizeof(r));
            r.op=FSOP_MOD_LIST_CLOSE;
            if(disk_fs_request(&r)!=0)failed=true;
        }
        vPortFree(dirs[head]);
        dirs[head]=NULL;
        head++;
    }
    for(;head<tail;head++)if(dirs[head])vPortFree(dirs[head]);
    if(failed) {
        osd_log("MCU JUKE: DIRECTORY SCAN FAILED");
        mod_jukebox_clear();
        return false;
    }
    if(s_count)qsort(s_tracks,s_count,sizeof(s_tracks[0]),track_cmp);
    osd_log("MCU JUKE: %u MODS %s%s",s_count,
            recursive?"TREE":"FOLDER",s_truncated?" (LIMIT)":"");
    osd_log("MCU JUKE: SEEN %u NONMOD %u DIR %u PATHLONG %u",
            entries,nonmod,dir_entries,longpath);
    return s_count!=0;
}
