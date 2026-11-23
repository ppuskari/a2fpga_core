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
/* Case-insensitive exact path match in the sorted playlist, -1 if absent. */
int mod_jukebox_find(const char *relative_file);
bool mod_jukebox_truncated(void);
/* True only for failed scanning (FatFS error / low heap / invalid path),
 * not for a successful but empty directory. Cleared by clear/new scan. */
bool mod_jukebox_last_error(void);
#endif
