/* Live song identity for MCU MOD menu. Single producer: modpcm FreeRTOS task;
 * readers (HID/menu thread) use a generation-stable snapshot. Not a control
 * channel: no HxCMOD, SD or SPI calls take place here. */
#ifndef MCU_MOD_NOW_PLAYING_H
#define MCU_MOD_NOW_PLAYING_H
#include <stdbool.h>
#include <stdint.h>

#define MOD_NOW_PLAYING_PATH_MAX 128u

typedef struct {
    char path[MOD_NOW_PLAYING_PATH_MAX];  /* FAT-volume-relative filename */
    unsigned track;                       /* 1-based in playlist, or 0 */
    unsigned total;                       /* playlist size, or 0 */
    bool active;                          /* set only once playback starts */
} mod_now_playing_t;

/* Only call publish/clear from the modpcm task. */
void mod_now_playing_publish(const char *path,unsigned track,unsigned total);
void mod_now_playing_clear(void);
/* True if snapshot was consistent; false during concurrent publication.
 * On failure, no caller-visible snapshot data is modified. */
bool mod_now_playing_snapshot(mod_now_playing_t *out);
uint32_t mod_now_playing_generation(void);

#endif
