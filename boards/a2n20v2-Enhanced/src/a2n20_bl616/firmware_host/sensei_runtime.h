#ifndef SENSEI_RUNTIME_H
#define SENSEI_RUNTIME_H

/* Runtime MOD selection and parsing. NO compiled-in songs or generated assets.
 * Current Stage A validates and opens a user-selected MOD; DOC PCM transfer
 * remains a separate Stage B and playback may NOT start until it completes.
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "sensei_mod_player.h"
#define SENSEI_PATH_CAP 128u
#define SENSEI_RUNTIME_MAX_FILE 65536u
#define SENSEI_RUNTIME_MAX_SAMPLE_BANK 49152u

typedef enum {
    SENSEI_RT_IDLE=0, SENSEI_RT_SELECTED=1, SENSEI_RT_LOADING=2,
    SENSEI_RT_READY_PCM=3, SENSEI_RT_PLAYING=4, SENSEI_RT_ERROR=5,
    SENSEI_RT_DONE=6
} sensei_runtime_status_t;

typedef struct {
    uint8_t *file;           /* Owned raw .MOD bytes, no precompiled rows */
    uint32_t file_size;
    uint8_t *pcm;            /* MOD: adapted; NTP: exact DOC-ready samples */
    uint32_t pcm_length;
    uint8_t *ntp_patterns;   /* retained P2W regression/compatibility buffer */
    const uint8_t *ntp_raw_patterns; /* view into owned .NTP file */
    uint8_t ntp_pattern_count;
    uint8_t ntp_instrument_map[64];
    uint8_t ntp_irq_instruments[32];
    uint8_t channel_pan[4];  /* NTP's 0..7 channels -> native DOC L/R */
    uint8_t source_ntp;      /* 0=MOD, 1=NTP v0/v2 DOC-ready samples */
    uint8_t ntp_version;     /* actual imported NTP version */
    uint8_t ntp_nonideal;    /* loops needing NTP-native IRQ replay */
    uint8_t catalog[32*8];   /* P2R attack/sustain WTP/RTS/CTRL/VOL/flags */
    uint8_t order_table[128];
    uint8_t order_count;
    sensei_mod_song_t song;
} sensei_runtime_module_t;

/* Menu thread selects a .MOD or .NTP by FAT path, not an instrument ID. */
bool sensei_runtime_choose(const char *relative_path);
bool sensei_runtime_pending(char *dst,size_t cap);
sensei_runtime_status_t sensei_runtime_status(void);
void sensei_runtime_set_status(sensei_runtime_status_t value);
/* P2U audition mode: 0=all, 1..4=one channel, 5=right pair,
 * 6=left pair. Selection applies on next song start, not mid-note. */
void sensei_runtime_set_audition_mode(uint8_t mode);
uint8_t sensei_runtime_audition_mode(void);
void sensei_runtime_request_stop(void);
bool sensei_runtime_take_stop_request(void);
/* Must run from BL616 tracker worker, through serialized disk_fs_request. */
bool sensei_runtime_load(const char *relative_path, sensei_runtime_module_t *out);
void sensei_runtime_free(sensei_runtime_module_t *out);

#endif
