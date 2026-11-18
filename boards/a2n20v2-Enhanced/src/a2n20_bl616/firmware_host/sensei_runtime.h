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
    SENSEI_RT_READY_PCM=3, SENSEI_RT_PLAYING=4, SENSEI_RT_ERROR=5
} sensei_runtime_status_t;

typedef struct {
    uint8_t *file;           /* Owned raw .MOD bytes, no precompiled rows */
    uint32_t file_size;
    uint8_t *pcm;            /* Adapted PCM for DOC RAM; generated at load time */
    uint32_t pcm_length;
    uint8_t catalog[32*4];   /* WTP, RTS, CTRL, VOL for 31 instruments */
    uint8_t order_table[128];
    uint8_t order_count;
    sensei_mod_song_t song;
} sensei_runtime_module_t;

/* Menu thread selects a file by relative FAT path, not an instrument ID. */
bool sensei_runtime_choose(const char *relative_path);
bool sensei_runtime_pending(char *dst,size_t cap);
sensei_runtime_status_t sensei_runtime_status(void);
/* Must run from BL616 tracker worker, through serialized disk_fs_request. */
bool sensei_runtime_load(const char *relative_path, sensei_runtime_module_t *out);
void sensei_runtime_free(sensei_runtime_module_t *out);

#endif
