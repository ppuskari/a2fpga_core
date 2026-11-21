#ifndef MCU_MOD_AUDIO_H
#define MCU_MOD_AUDIO_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
typedef enum {
    MOD_PCM_IDLE=0, MOD_PCM_SELECTED=1, MOD_PCM_LOADING=2,
    MOD_PCM_PLAYING=3, MOD_PCM_STOPPED=4, MOD_PCM_ERROR=5
} mod_pcm_status_t;
bool mod_audio_choose(const char *relative_path);
mod_pcm_status_t mod_audio_status(void);
void mod_audio_request_stop(void);
/* Replay the last selected FAT .MOD from the MCU mailbox (no DOC). */
bool mod_audio_replay_last(void);
void mod_audio_task(void *arg);
#endif
