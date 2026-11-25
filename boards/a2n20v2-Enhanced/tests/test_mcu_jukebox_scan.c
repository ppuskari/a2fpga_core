/* Portable J1 regression: independent FAT broker playlist scans, sorting,
 * recursive enumeration and intentional non-MOD filtering. */
#include "mcu_mod_jukebox.h"
#include "disk.h"
#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { const char *name; unsigned attr; } ent_t;
static const ent_t root[]={{"c.mod",0},{"A",0x10},{"note.txt",0},{"MOD.alpha",0},{"B.MOD",0},{NULL,0}};
static const ent_t sub[]={{"1.mod",0},{"Z",0x10},{NULL,0}};
static const ent_t deep[]={{"last.mod",0},{NULL,0}};
static const ent_t *cur;
static size_t cursor;
static bool stress_large, stress_long, inject_read_error, empty_folder;
static void check(bool cond,const char *msg) {
    if(!cond){fprintf(stderr,"FAIL JUKE: %s\n",msg);exit(1);}
}
void *pvPortMalloc(size_t n){return malloc(n);}
void vPortFree(void *p){free(p);}
void osd_log(const char *fmt,...) {(void)fmt;}
void vTaskSuspendAll(void) {}
int xTaskResumeAll(void) {return 1;}

/* Simulate real libc OOM without invoking the fatal FreeRTOS hook. */
static bool reject_malloc;
static size_t reject_larger_than;
static unsigned alloc_calls;
static unsigned maximum_requested;
extern void *__real_malloc(size_t n);
void *__wrap_malloc(size_t n)
{
    ++alloc_calls;
    if(n>maximum_requested)maximum_requested=(unsigned)n;
    return (reject_malloc || (reject_larger_than && n>reject_larger_than)) ?
        NULL : __real_malloc(n);
}

int disk_fs_request(fs_req_t *r)
{
    if(r->op==FSOP_MOD_LIST_CLOSE){cur=NULL;return 0;}
    if(r->op==FSOP_MOD_LIST_OPEN) {
        if(!strcmp(r->path,""))cur=root;
        else if(!strcmp(r->path,"A"))cur=sub;
        else if(!strcmp(r->path,"A/Z"))cur=deep;
        else if(!strcmp(r->path,"PROTRACKER/2"))cur=root;
        else if(!strcmp(r->path,"PROTRACKER/LONG"))cur=root;
        else if(!strcmp(r->path,"EMPTY"))cur=deep;
        else return -1;
        stress_large=!strcmp(r->path,"PROTRACKER/2") ||
                     !strcmp(r->path,"PROTRACKER/LONG");
        stress_long=!strcmp(r->path,"PROTRACKER/LONG");
        empty_folder=!strcmp(r->path,"EMPTY");
        cursor=0;
        return 0;
    }
    if(r->op==FSOP_MOD_LIST_NEXT && cur) {
        r->name[0]=0;
        if(inject_read_error && cursor==12u)return 1; /* FR_DISK_ERR */
        if(stress_large) {
            if(cursor<500u) {
                if(stress_long) {
                    /* 62-byte legal filename, including .MOD, case-insensitive
                     * order by the fixed eight-character TRACKnnn prefix. */
                    snprintf(r->name,sizeof r->name,"TRACK%03u",
                             (unsigned)(499u-cursor));
                    memset(r->name+8,'X',50u);
                    memcpy(r->name+58,".MOD",5u);
                } else {
                    snprintf(r->name,sizeof r->name,"TRACK%03u.MOD",
                             (unsigned)(499u-cursor));
                }
                r->attr=0;
            }
            cursor++;
            return 0;
        }
        if(empty_folder)return 0;
        const ent_t *e=&cur[cursor];
        r->name[0]=0;
        if(e->name) {
            snprintf(r->name,sizeof r->name,"%s",e->name);
            r->attr=(uint8_t)e->attr;
            cursor++;
        }
        return 0;
    }
    return -1;
}
int main(void)
{
    check(mod_jukebox_scan("",false),"root folder scan");
    check(mod_jukebox_count()==3,"root folder accepts both MOD filename conventions");
    check(!strcmp(mod_jukebox_track(0),"B.MOD"),"case-insensitive root sort 0");
    check(!strcmp(mod_jukebox_track(1),"c.mod"),"case-insensitive root sort 1");
    check(!strcmp(mod_jukebox_track(2),"MOD.alpha"),"Amiga prefix MOD entry sorted");
    check(!mod_jukebox_truncated(),"root not truncated");
    check(mod_jukebox_find("c.mod")==1,"resume selected final root track");
    check(mod_jukebox_find("C.MOD")==1,"case-insensitive saved path");
    check(mod_jukebox_find("B.mod")==0,"starting file at index zero");
    check(mod_jukebox_find("notfound.mod")==-1,"missing file never falls back");
    check(mod_jukebox_find("../c.mod")==-1,"no substring fallback");
    check(mod_jukebox_find(NULL)==-1,"null path never matches");
    check(mod_jukebox_scan("",true),"recursive tree scan");
    check(mod_jukebox_count()==5,"tree has five MOD files");
    check(!strcmp(mod_jukebox_track(0),"A/1.mod"),"nested alphabetic sort 0");
    check(!strcmp(mod_jukebox_track(1),"A/Z/last.mod"),"nested alphabetic sort 1");
    check(!strcmp(mod_jukebox_track(2),"B.MOD"),"nested alphabetic sort 2");
    check(!strcmp(mod_jukebox_track(3),"c.mod"),"nested alphabetic sort 3");
    check(!strcmp(mod_jukebox_track(4),"MOD.alpha"),"nested Amiga prefix sort 4");
    check(mod_jukebox_find("A/Z/LAST.MOD")==1,"subdirectory path lookup");
    check(mod_jukebox_find("c.mod")==3,"selected recursive last track");
    check(mod_jukebox_find("A/missing.mod")==-1,"no silent track zero");
    check(mod_jukebox_find("mod.ALPHA")==4,"case-insensitive prefix start-file lookup");
    check(mod_jukebox_find("c.mo")==-1,"no prefix match");
    check(!mod_jukebox_scan("../escape",true),"reject parent traversal");
    mod_jukebox_clear();
    check(mod_jukebox_count()==0,"clear playlist releases tracks");
    reject_malloc=true;
    check(!mod_jukebox_scan("",false),
          "recoverable jukebox OOM must fail without fatal FreeRTOS hook");
    reject_malloc=false;
    check(mod_jukebox_last_error(),"OOM distinguished from an empty directory");
    check(mod_jukebox_count()==0,"failed OOM scan leaves no playlist");
    check(!mod_jukebox_scan("EMPTY",false),"empty folder returns false");
    check(!mod_jukebox_last_error(),"empty folder is not a scan failure");
    check(mod_jukebox_scan("",false),"scan recovers after low-heap condition");
    check(mod_jukebox_count()==3,"recovered playlist contains all MODs");
    mod_jukebox_clear();
    const unsigned allocated_before=alloc_calls;
    check(mod_jukebox_scan("PROTRACKER/2",false),
          "500 MODs scan with directory already open in M2 Apple browser");
    check(!mod_jukebox_last_error(),"500 MOD scan completed without error");
    check(mod_jukebox_count()==500u,"all 500 MODs collected");
    check(!strcmp(mod_jukebox_track(0),"PROTRACKER/2/TRACK000.MOD"),
          "500 MOD catalog globally sorted ascending");
    check(!strcmp(mod_jukebox_track(499),"PROTRACKER/2/TRACK499.MOD"),
          "last MOD is present and seekable");
    check(alloc_calls-allocated_before<12u,
          "500 filenames use ~7 small allocations, not 500 duplicated paths");
    check(maximum_requested<=1024u,
          "no 2-KiB-or-larger jukebox allocation");
    check(mod_jukebox_find("PROTRACKER/2/TRACK009.MOD")==9,
          "selected 10th MOD position resolves correctly");
    /* Reproduce the original 500-track failure with much longer filenames.
     * With 1-KiB allocations blocked by simulated fragmentation the scan
     * must transparently recover using 512-byte chunks. Full selected
     * file paths are reconstructed identically for ProDOS start-at-file. */
    reject_larger_than=512u;
    check(mod_jukebox_scan("PROTRACKER/LONG",false),
          "500 long-name MODs fit 512-byte fallback blocks");
    check(mod_jukebox_count()==500u,"all 500 long names retained");
    char selected[MOD_JUKE_PATH_CAP];
    snprintf(selected,sizeof selected,"PROTRACKER/LONG/TRACK%03u",494u);
    const size_t prefix_len=strlen(selected);
    memset(selected+prefix_len,'X',50u);
    memcpy(selected+prefix_len+50u,".MOD",5u);
    check(mod_jukebox_find(selected)==494,
          "long selected entry at previous failure position 494 resolves");
    check(!strcmp(mod_jukebox_track(494),selected),
          "full path reconstructed exactly, preserving filename and extension");
    check(mod_jukebox_track(499)!=NULL,
          "last long filename remains playable");
    mod_jukebox_clear();
    reject_larger_than=256u;
    check(mod_jukebox_scan("PROTRACKER/LONG",false),
          "500 long MOD names survive minimum 256-byte allocation ceiling");
    check(mod_jukebox_count()==500u,
          "512-track capacity unaffected by small malloc blocks");
    check(mod_jukebox_find(selected)==494,
          "exact long-name lookup preserved under 256-byte fallback");
    mod_jukebox_clear();
    reject_larger_than=0u;
    inject_read_error=true;
    check(!mod_jukebox_scan("PROTRACKER/2",false),
          "injected FatFS readdir error must not masquerade as no MODs");
    check(mod_jukebox_last_error(),"FatFS failure code distinct from empty folder");
    check(mod_jukebox_count()==0,"partial list discarded on failed read");
    inject_read_error=false;
    check(mod_jukebox_scan("PROTRACKER/2",false),
          "directory scan can restart after genuine FatFS error");
    mod_jukebox_clear();
    puts("PASS M3: compact sorted FAT jukebox, interned dirs, 500 long names, 512/256-byte heap fallback, exact start-file and OOM");
    return 0;
}
