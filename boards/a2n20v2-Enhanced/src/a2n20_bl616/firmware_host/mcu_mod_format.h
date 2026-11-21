/* Bounded parser for HxCMOD 1-8 channel MODs, including 15 samples. */
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
    uint8_t song_length,pattern_count,sample_count,channels;
} mod_format_t;

/* header contains first MOD_HEADER_PROBE bytes; file_bytes is actual size.
 * Accept 31-sample 1..8-channel HxCMOD signatures and classic
 * 15-sample 4-channel layouts. Reject unknown signatures, truncated data,
 * malformed headers and all XM/S3M/IT formats; these require new decoders. */
bool mod_format_probe(const uint8_t header[MOD_HEADER_PROBE],
                      uint32_t file_bytes,mod_format_t *out);
#endif
