#include "mcu_mod_now_playing.h"
#include <stddef.h>

/* Single producer (modpcm), multiple readers (menu/diagnostics).
 * Odd generation marks publication in progress; even means complete.
 * Atomic byte transfers avoid data races even when a reader overlaps a
 * filename update. No mutex, allocation, or SPI traffic on this path. */
static uint32_t s_generation;
static char s_path[MOD_NOW_PLAYING_PATH_MAX];
static unsigned s_track,s_total;
static bool s_active;

void mod_now_playing_publish(const char *path,unsigned track,unsigned total)
{
    const bool active=path && path[0];
    size_t n=0u;
    if(active)
        while(n+1u<sizeof(s_path) && path[n])++n;
    const uint32_t g=__atomic_load_n(&s_generation,__ATOMIC_RELAXED);
    __atomic_store_n(&s_generation,g+1u,__ATOMIC_RELEASE);
    for(size_t i=0;i<sizeof(s_path);i++)
        __atomic_store_n(&s_path[i],(active && i<n) ? path[i] : '\0',
                         __ATOMIC_RELAXED);
    __atomic_store_n(&s_track,active?track:0u,__ATOMIC_RELAXED);
    __atomic_store_n(&s_total,active?total:0u,__ATOMIC_RELAXED);
    __atomic_store_n(&s_active,active,__ATOMIC_RELAXED);
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
    for(unsigned tries=0;tries<3;tries++) {
        const uint32_t before=__atomic_load_n(&s_generation,__ATOMIC_ACQUIRE);
        if(before&1u)continue;
        mod_now_playing_t copy;
        for(size_t i=0;i<sizeof(copy.path);i++)
            copy.path[i]=__atomic_load_n(&s_path[i],__ATOMIC_RELAXED);
        copy.track=__atomic_load_n(&s_track,__ATOMIC_RELAXED);
        copy.total=__atomic_load_n(&s_total,__ATOMIC_RELAXED);
        copy.active=__atomic_load_n(&s_active,__ATOMIC_RELAXED);
        __atomic_thread_fence(__ATOMIC_ACQUIRE);
        const uint32_t after=__atomic_load_n(&s_generation,__ATOMIC_ACQUIRE);
        if(before!=after || (after&1u))continue;
        copy.path[sizeof(copy.path)-1u]=0;
        *out=copy;
        return true;
    }
    return false;
}
