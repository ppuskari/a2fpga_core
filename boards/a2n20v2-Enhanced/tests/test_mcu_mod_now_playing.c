/* J2R2: no torn NOW PLAYING filename/playlist position during menu reads. */
#include "mcu_mod_now_playing.h"
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned completed;
static void require(int condition,const char *message)
{
    if(!condition) { fprintf(stderr,"FAIL NOW PLAYING: %s\n",message);exit(1); }
}
static void *writer(void *arg)
{
    (void)arg;
    for(unsigned i=1;i<=40000;i++) {
        char name[MOD_NOW_PLAYING_PATH_MAX];
        unsigned track=(i%500u)+1u;
        snprintf(name,sizeof name,"songs/%u.MOD",track);
        mod_now_playing_publish(name,track,500u);
        if(!(i%7u))mod_now_playing_clear();
    }
    __atomic_store_n(&completed,1u,__ATOMIC_RELEASE);
    return NULL;
}
int main(void)
{
    mod_now_playing_t info={0};
    uint32_t before=mod_now_playing_generation();
    require(mod_now_playing_snapshot(&info),"initial snapshot");
    require(!info.active,"initial state not empty");
    require(!mod_now_playing_snapshot(NULL),"null read should fail");
    pthread_t thread;
    require(!pthread_create(&thread,NULL,writer,NULL),"create writer");
    unsigned snapshots=0;
    while(!__atomic_load_n(&completed,__ATOMIC_ACQUIRE)) {
        if(!mod_now_playing_snapshot(&info))continue;
        ++snapshots;
        if(info.active) {
            unsigned n=0;
            require(sscanf(info.path,"songs/%u.MOD",&n)==1,
                    "partial/torn filename");
            require(n==info.track && info.total==500u,
                    "filename, current track and total must be atomic");
        } else {
            require(info.path[0]=='\0' && info.track==0u && info.total==0u,
                    "cleared snapshot retains previous song");
        }
    }
    require(!pthread_join(thread,NULL),"join writer");
    mod_now_playing_publish("albums/next_song.mod",17u,118u);
    require(mod_now_playing_snapshot(&info),"final snapshot");
    require(info.active && info.track==17u && info.total==118u,
            "playlist position");
    require(!strcmp(info.path,"albums/next_song.mod"),"full relative filename");
    char oversized[200];memset(oversized,'a',sizeof oversized);
    oversized[sizeof oversized-1u]='\0';
    mod_now_playing_publish(oversized,1u,1u);
    require(mod_now_playing_snapshot(&info),"oversized filename snapshot");
    require(info.path[MOD_NOW_PLAYING_PATH_MAX-1u]=='\0',
            "oversized filename not bounded");
    mod_now_playing_clear();
    require(mod_now_playing_snapshot(&info) && !info.active,
            "stop clears NOW PLAYING");
    require(mod_now_playing_generation()>before,
            "menu refresh generation not advancing");
    printf("PASS J2R2: coherent live now-playing snapshots, %u concurrent reads\n",
           snapshots);
    return 0;
}
