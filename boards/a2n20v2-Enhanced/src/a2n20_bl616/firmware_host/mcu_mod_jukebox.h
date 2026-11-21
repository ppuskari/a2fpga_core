#ifndef MCU_MOD_JUKEBOX_H
#define MCU_MOD_JUKEBOX_H
#include <stdbool.h>
/* Called exclusively by the MOD PCM task. All FAT operations go through
 * disk_fs_request(), never directly from this thread. */
#define MOD_JUKE_PATH_CAP 128u
#define MOD_JUKE_MAX_TRACKS 512u
bool mod_jukebox_scan(const char *root, bool recursive);
void mod_jukebox_clear(void);
unsigned mod_jukebox_count(void);
const char *mod_jukebox_track(unsigned index);
bool mod_jukebox_truncated(void);
#endif
