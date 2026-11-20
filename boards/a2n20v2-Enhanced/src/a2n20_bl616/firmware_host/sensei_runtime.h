#ifndef SENSEI_RUNTIME_H
#define SENSEI_RUNTIME_H
/*
 * SenseiPlay8 P2AA: native NTP only, FAT32 USB/SD runtime loader.
 * The original NTP file owns raw score bytes and DOC-ready PCM waveforms.
 * No MOD decoder, converted patterns, or duplicate score allocations.
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#define SENSEI_PATH_CAP 128u
#define SENSEI_RUNTIME_MAX_FILE 65536u

typedef enum {
    SENSEI_RT_IDLE=0, SENSEI_RT_SELECTED=1, SENSEI_RT_LOADING=2,
    SENSEI_RT_READY_PCM=3, SENSEI_RT_PLAYING=4, SENSEI_RT_ERROR=5,
    SENSEI_RT_DONE=6
} sensei_runtime_status_t;

typedef struct {
    uint8_t *file;               /* owned original .NTP (score + samples) */
    uint32_t file_size;
    uint8_t *pcm;                /* owned DOC-ready 8-bit sample bank */
    uint32_t pcm_length;
    const uint8_t *ntp_raw_patterns; /* view into file, never copied */
    uint8_t ntp_pattern_count;
    uint8_t ntp_instrument_map[64];
    uint8_t ntp_irq_instruments[32];
    uint8_t channel_pan[4];
    uint8_t ntp_version;
    uint8_t ntp_nonideal;
    uint8_t catalog[32*8];
    uint8_t order_table[128];
    uint8_t order_count;
} sensei_runtime_module_t;

bool sensei_runtime_choose(const char *relative_path);
bool sensei_runtime_pending(char *dst,size_t cap);
sensei_runtime_status_t sensei_runtime_status(void);
void sensei_runtime_set_status(sensei_runtime_status_t value);
void sensei_runtime_set_audition_mode(uint8_t mode);
uint8_t sensei_runtime_audition_mode(void);
void sensei_runtime_request_stop(void);
bool sensei_runtime_take_stop_request(void);
bool sensei_runtime_load(const char *relative_path, sensei_runtime_module_t *m);
void sensei_runtime_free(sensei_runtime_module_t *m);
#endif
