/* MOD filename conventions shared by the console picker, mailbox browser,
 * J2R11 jukebox and HxCMOD loader. Original Amiga modules commonly use
 * MOD.SONGNAME (prefix); DOS/Windows collections use SONGNAME.MOD (suffix).
 * Playback still probes and validates the actual file contents.
 */
#ifndef A2FPGA_MOD_FILENAME_H
#define A2FPGA_MOD_FILENAME_H

#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <ctype.h>

static inline bool mod_filename_matches(const char *path)
{
    if(!path)return false;
    const char *name=strrchr(path,'/');
    name=name?name+1:path;
    const size_t n=strlen(name);
    if(n<5u)return false;
    const bool suffix=name[n-4]=='.' &&
        tolower((unsigned char)name[n-3])=='m' &&
        tolower((unsigned char)name[n-2])=='o' &&
        tolower((unsigned char)name[n-1])=='d';
    const bool prefix=tolower((unsigned char)name[0])=='m' &&
        tolower((unsigned char)name[1])=='o' &&
        tolower((unsigned char)name[2])=='d' &&
        name[3]=='.' && name[4]!=0;
    return suffix || prefix;
}
#endif
