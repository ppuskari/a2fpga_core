#include "mcu_mod_gain.h"
#include <stdint.h>

/* Q16 amplitudes for integer 0..12 dB, rounded from 10^(dB/20).
 * Fixed point avoids any FPU/libm dependency in the render task. */
static const uint32_t s_gain_q16[MOD_GAIN_MAX_DB+1u]={
    65536u,73533u,82505u,92572u,103868u,116541u,130762u,
    146717u,164619u,184706u,207243u,232531u,260904u
};
static unsigned s_db=MOD_GAIN_DEFAULT_DB;
static uint32_t s_limiter_q16;
void mod_gain_set_db(unsigned db)
{
    if(db>MOD_GAIN_MAX_DB)db=MOD_GAIN_MAX_DB;
    __atomic_store_n(&s_db,db,__ATOMIC_RELEASE);
}
unsigned mod_gain_get_db(void)
{
    return __atomic_load_n(&s_db,__ATOMIC_ACQUIRE);
}
void mod_gain_reset(void)
{
    s_limiter_q16=0;
}
void mod_gain_apply(int16_t *pcm,unsigned frames)
{
    if(!pcm || !frames)return;
    const uint32_t wanted=s_gain_q16[mod_gain_get_db()];
    uint32_t peak=0;
    for(unsigned i=0;i<frames*2u;i++){
        const int32_t v=pcm[i];
        const uint32_t amp=(uint32_t)(v<0?-v:v);
        if(amp>peak)peak=amp;
    }
    uint32_t target=wanted;
    if(peak) {
        const uint32_t safe=(MOD_GAIN_CEILING*65536u)/peak;
        if(target>safe)target=safe;
    }
    /* One-block lookahead protects against overshoot. Fast attenuation for
     * a new loud block, slow gain recovery (~0.6s at 256/44.1kHz). This
     * preserves stereo balance and does not alter tracker effects. */
    if(!s_limiter_q16 || target<s_limiter_q16)
        s_limiter_q16=target;
    else if(target>s_limiter_q16) {
        uint32_t step=(target-s_limiter_q16)/96u;
        if(!step)step=1u;
        s_limiter_q16+=step;
        if(s_limiter_q16>target)s_limiter_q16=target;
    }
    const uint32_t gain=s_limiter_q16;
    for(unsigned i=0;i<frames*2u;i++){
        int32_t v=(int32_t)(((int64_t)pcm[i]*(int64_t)gain)/65536);
        /* Final safety against quantization or future changes. */
        if(v>MOD_GAIN_CEILING)v=MOD_GAIN_CEILING;
        if(v< -MOD_GAIN_CEILING)v= -MOD_GAIN_CEILING;
        pcm[i]=(int16_t)v;
    }
}
