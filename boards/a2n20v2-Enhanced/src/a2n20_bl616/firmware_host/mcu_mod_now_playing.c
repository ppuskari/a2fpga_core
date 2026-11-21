#include "mcu_mod_now_playing.h"
#include <string.h>

/* Odd = producer writing; even = complete snapshot. Full name + playlist
 * position are published atomically as a logical record. Only modpcm writes,
 * and no allocation, SPI or mutex exists on this path. */
static volatile uint32_t s_generation;
static char s_path[MOD_NOW_PLAYING_PATH_MAX];
static unsigned s_track,s_total;
static bool s_active;

void mod_now_playing_publish(const char *path,unsigned track,unsigned total)
{
    const uint32_t g=__atomic_load_n(&s_generation,__ATOMIC_RELAXED);
    __atomic_store_n(&s_generation,g+1u,__ATOMIC_RELEASE);
    if(path && path[0]) {
        size_t n=0u;
        while(n+1u<sizeof(s_path) && path[n])++n;
        memcpy(s_path,path,n);
        s_path[n]=0;
        s_track=track;
        s_total=total;
        s_active=true;
    } else {
        s_path[0]=0;
        s_track=s_total=0u;
        s_active=false;
    }
    __atomic_store_n(&s_generation,g+2u,__ATOMIC_RELEASE);
}
void mod_now_playing_clear(void)
{
    mod_now_playing_publish(NULL,0u,0u);
}
uint32_t mod_now_playing_generation(void)
{
    return __atomic_load_n(&s_generation,__ATOMIC_ACQUIRE);
}
bool mod_now_playing_snapshot(mod_now_playing_t *out)
{
    if(!out)return false;
    for(unsigned try_idx=0;try_idx<3;try_idx++) {
        uint32_t before=__atomic_load_n(&s_generation,__ATOMIC_ACQUIRE);
        if(before&1u)continue;
        mod_now_playing_t copy;
        memcpy(copy.path,s_path,sizeof(copy.path));
        copy.track=s_track;
        copy.total=s_total;
        copy.active=s_active;
        __atomic_thread_fence(__ATOMIC_ACQUIRE);
        uint32_t after=__atomic_load_n(&s_generation,__ATOMIC_ACQUIRE);
        if(before!=after || (after&1u))continue;
        copy.path[sizeof(copy.path)-1u]=0;
        *out=copy;
        return true;
    }
    return false;
}
