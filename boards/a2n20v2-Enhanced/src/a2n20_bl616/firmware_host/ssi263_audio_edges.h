/* P10-R7: PCM16 attack edge smoother.  No SSI control/timing changes.
 *
 * Apply only after sustained digital near-silence, NOT on every phoneme
 * register write. This protects /s/, /sh/, /f/ and intentional stop bursts
 * inside running words. No floating point or heap use in the shaper.
 *
 * A 2.5ms linear attack is a cautious experiment against the abrupt start
 * of R6 output.  It does not pretend to repair all Pico model noise.
 */
#ifndef SSI263_AUDIO_EDGES_H
#define SSI263_AUDIO_EDGES_H
#include <stdint.h>

typedef struct {
    uint32_t quiet_run;
    uint32_t quiet_samples;
    uint32_t attack_samples;
    uint32_t attack_remaining;
    uint32_t attacks;
    uint16_t quiet_abs;
    uint8_t armed;
} ssi263_audio_edges;

static inline void ssi263_audio_edges_init(
    ssi263_audio_edges *s, uint32_t sample_hz,
    uint32_t quiet_ms, uint32_t attack_us, uint16_t quiet_abs)
{
    s->quiet_samples=(uint32_t)(((uint64_t)sample_hz*quiet_ms+999u)/1000u);
    if(!s->quiet_samples)s->quiet_samples=1u;
    s->attack_samples=(uint32_t)(((uint64_t)sample_hz*attack_us+999999u)/1000000u);
    s->quiet_abs=quiet_abs;
    s->quiet_run=s->quiet_samples;
    s->armed=1u;
    s->attack_remaining=0u;
    s->attacks=0u;
}

static inline void ssi263_audio_edges_rearm(ssi263_audio_edges *s)
{
    s->quiet_run=s->quiet_samples;
    s->armed=1u;
    s->attack_remaining=0u;
}

static inline int16_t ssi263_audio_edges_sample(
    ssi263_audio_edges *s, int16_t in)
{
    int32_t value=(int32_t)in;
    uint32_t absval=value<0 ? (uint32_t)(-value) : (uint32_t)value;
    if(absval <= s->quiet_abs) {
        if(s->quiet_run<s->quiet_samples)s->quiet_run++;
        if(s->quiet_run>=s->quiet_samples) {
            s->armed=1u;
            s->attack_remaining=0u;
        }
    } else {
        s->quiet_run=0u;
        if(s->armed) {
            s->armed=0u;
            s->attack_remaining=s->attack_samples;
            s->attacks++;
        }
    }
    if(s->attack_remaining && s->attack_samples) {
        uint32_t index=s->attack_samples-s->attack_remaining+1u;
        value=(value*(int32_t)index)/(int32_t)s->attack_samples;
        s->attack_remaining--;
    }
    return (int16_t)value;
}

#endif
