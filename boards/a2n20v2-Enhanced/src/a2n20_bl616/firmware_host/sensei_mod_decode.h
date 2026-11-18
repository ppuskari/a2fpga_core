#ifndef SENSEI_MOD_DECODE_H
#define SENSEI_MOD_DECODE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Raw ProTracker loader, no offline conversion, no static song tables.
 * Caller retains file in RAM and supplies output PCM work buffer. */
typedef struct {
    uint32_t pattern_offset;    /* byte offset into original MOD */
    uint16_t pattern_count;
    uint8_t order_count;
    uint8_t orders[128];
    uint8_t catalog[32*8];      /* index 1..31 x [attack, sustain, flags] */
    uint32_t doc_pcm_bytes;
    uint32_t file_sample_bytes;
} sensei_mod_decoded_t;

bool sensei_mod_decode(const uint8_t *file,size_t length,
                       uint8_t *pcm,size_t pcm_cap,
                       sensei_mod_decoded_t *decoded);
#endif
