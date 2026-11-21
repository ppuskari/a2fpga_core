/* Bounded parser for four-channel ProTracker MODs, including 15 samples. */
#ifndef MCU_MOD_FORMAT_H
#define MCU_MOD_FORMAT_H
#include <stdbool.h>
#include <stdint.h>
#define MOD_HEADER_PROBE 1084u
#define MOD_TOTAL_FILE_MAX (2u*1024u*1024u)
typedef struct {
    uint32_t header_bytes;
    uint32_t pattern_bytes;
    uint32_t prefix_bytes;
    uint32_t sample_bytes;
    uint32_t lengths[31]; /* bytes, not words */
    uint8_t song_length,pattern_count,sample_count;
} mod_format_t;

/* header contains first MOD_HEADER_PROBE bytes; file_bytes is actual size.
 * Accept only standard 4-channel 31/15-instrument layouts. Returns false
 * on unknown signatures, truncated patterns/samples, overflow or bad loops. */
bool mod_format_probe(const uint8_t header[MOD_HEADER_PROBE],
                      uint32_t file_bytes,mod_format_t *out);
#endif
