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
extern void *__real_malloc(size_t n);
void *__wrap_malloc(size_t n)
{
    return reject_malloc ? NULL : __real_malloc(n);
}

int disk_fs_request(fs_req_t *r)
{
    if(r->op==FSOP_MOD_LIST_CLOSE){cur=NULL;return 0;}
    if(r->op==FSOP_MOD_LIST_OPEN) {
        if(!strcmp(r->path,""))cur=root;
        else if(!strcmp(r->path,"A"))cur=sub;
        else if(!strcmp(r->path,"A/Z"))cur=deep;
        else return -1;
        cursor=0;
        return 0;
    }
    if(r->op==FSOP_MOD_LIST_NEXT && cur) {
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
    puts("PASS J2R11: sorted FAT jukebox, exact start-file lookup and missing handling");
    return 0;
}
