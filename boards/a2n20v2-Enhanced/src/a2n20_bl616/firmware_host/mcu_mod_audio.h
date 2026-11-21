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
/* J1: select a FAT folder and play each four-channel .MOD once, in order.
 * "from last" uses the folder of the most recently chosen MOD; if none
 * exists it uses the FAT volume root. */
bool mod_audio_jukebox_start(const char *relative_dir, bool recursive);
void mod_audio_jukebox_from_last(bool recursive);
bool mod_audio_next(void);
bool mod_audio_previous(void);
void mod_audio_set_play_once(bool once);
bool mod_audio_play_once(void);
unsigned mod_audio_jukebox_count(void);
/* Menu-only snapshot of the asynchronous playlist scan. The generation
 * increments on queue/scan/completion/clear to prompt UI repaint. */
typedef enum {
    MOD_JUKE_IDLE=0, MOD_JUKE_QUEUED, MOD_JUKE_SCANNING,
    MOD_JUKE_READY, MOD_JUKE_EMPTY
} mod_jukebox_scan_state_t;
mod_jukebox_scan_state_t mod_audio_jukebox_scan_state(void);
uint32_t mod_audio_jukebox_generation(void);
void mod_audio_task(void *arg);
#endif
