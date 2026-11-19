#ifndef SENSEI_NTP_IMPORT_H
#define SENSEI_NTP_IMPORT_H
/*
 * P2W NinjaTrackerPlus v0 and v2 reader (v1 intentionally unsupported).
 *
 * Format from Jesse Blue/NinjaForce's original file_format.txt and
 * ntpconverter_lib.php; no upstream source is bundled. The original NTP
 * contains DOC-offset 8-bit PCM. We copy those bytes without any conversion,
 * including NTP's chosen zero sentinels and its loop optimizations.
 *
 * This first pass reuses the P2U ProTracker effect scheduler after mapping
 * NTP notes to periods; it is NOT a port of the NTP 65816 replay engine.
 */
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#define SENSEI_NTP_MAX_PATTERN_BYTES 65536u
#define SENSEI_NTP_MAX_WAVE_BYTES 65536u
typedef struct {
    uint32_t pattern_bytes, pcm_bytes;
    uint8_t orders[128], order_count, pattern_count;
    uint8_t catalog[32u*8u];
    uint8_t channel_pan[4]; /* 0x10=left DOC output, 0=right */
    uint8_t logical_instruments;
    uint8_t nonideal_pairs;
    uint8_t raw_instruments;
    uint8_t ntp_version;
    uint32_t pattern_offset; /* raw original NTP records in input file */
    uint8_t instrument_map[64]; /* original NTP record -> DOC catalog index */
    uint8_t irq_instruments[32]; /* type-2/nonideal-sustain must retarget */
} sensei_ntp_decoded_t;
/*
 * Two-pass API: first call with pcm==NULL,patterns==NULL for lengths.
 * Second call with both buffers provided. Audio bytes are not transformed.
 * Versions 0 and 2, four tracks, no streaming, max 31 logical instruments;
 * reject unsupported variants before uploading sound RAM.
 */
bool sensei_ntp_import(const uint8_t *ntp,size_t len,
                       uint8_t *pcm,size_t pcm_cap,
                       uint8_t *patterns,size_t patterns_cap,
                       sensei_ntp_decoded_t *out);
#endif
