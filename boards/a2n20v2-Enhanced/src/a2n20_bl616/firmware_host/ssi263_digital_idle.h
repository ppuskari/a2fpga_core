/* P10-R10: conservative SSI-263 digital idle control.
 *
 * The hardware A/R request means READY, not necessarily silence. Never
 * infer silence from A/R alone or elapsed time since an SSI register write.
 * Only skip synthesis after a sustained run of exactly-zero PCM16 output
 * while the model asserts A/R. Keep FPGA FIFO supplied with zero blocks.
 *
 * Any Apple SSI register write wakes the model BEFORE the write is applied.
 * The model's ssi263_skip() discards silent filter history, so qualify
 * reactivation by comparing next phonemes on host and on hardware.
 *
 * Plain C99 helper, no FreeRTOS/BL616 dependency; unit-testable on host.
 */
#ifndef SSI263_DIGITAL_IDLE_H
#define SSI263_DIGITAL_IDLE_H

#include <stdint.h>
#include <stdbool.h>

typedef struct {
    uint32_t needed_zeros;
    uint32_t consecutive_zeros;
    uint32_t skipped_blocks;
    uint32_t wakes;
    bool skipping;
} ssi263_digital_idle;

static inline void ssi263_digital_idle_init(ssi263_digital_idle *s,
                                             uint32_t hz, uint32_t quiet_ms)
{
    s->needed_zeros=(uint32_t)(((uint64_t)hz * quiet_ms + 999u) / 1000u);
    if (s->needed_zeros == 0u) s->needed_zeros=1u;
    s->consecutive_zeros=0u;
    s->skipped_blocks=0u;
    s->wakes=0u;
    s->skipping=false;
}

static inline void ssi263_digital_idle_reset(ssi263_digital_idle *s)
{
    s->consecutive_zeros=0u;
    s->skipping=false;
}

static inline void ssi263_digital_idle_write(ssi263_digital_idle *s)
{
    if (s->skipping) ++s->wakes;
    ssi263_digital_idle_reset(s);
}

static inline bool ssi263_digital_idle_can_skip(ssi263_digital_idle *s,
                                                bool ar_ready)
{
    if (s->skipping && ar_ready) return true;
    if (!ar_ready) ssi263_digital_idle_reset(s);
    return false;
}

static inline void ssi263_digital_idle_skipped(ssi263_digital_idle *s)
{
    ++s->skipped_blocks;
}

static inline void ssi263_digital_idle_observe(ssi263_digital_idle *s,
                                                const short *pcm,
                                                uint32_t count, bool ar_ready)
{
    if (!ar_ready) {
        ssi263_digital_idle_reset(s);
        return;
    }
    for (uint32_t i=0; i<count; ++i) {
        if (pcm[i] != 0) {
            ssi263_digital_idle_reset(s);
            return;
        }
    }
    /* Saturating add so this counter never wraps, even after long soaks. */
    if (s->consecutive_zeros < s->needed_zeros) {
        uint32_t missing=s->needed_zeros-s->consecutive_zeros;
        s->consecutive_zeros+=(count < missing ? count : missing);
    }
    if (s->consecutive_zeros >= s->needed_zeros) s->skipping=true;
}

#endif /* SSI263_DIGITAL_IDLE_H */
