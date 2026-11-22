/* Shared MOD naming regression for Apple/BL616 browser, console and jukebox. */
#include <assert.h>
#include <stdio.h>
#include "mod_filename.h"
int main(void)
{
    assert(mod_filename_matches("song.mod"));
    assert(mod_filename_matches("SONG.MOD"));
    assert(mod_filename_matches("Music/1/a.mod"));
    assert(mod_filename_matches("MOD.SongName"));
    assert(mod_filename_matches("mod.a"));
    assert(mod_filename_matches("Music/1/MoD.SONG NAME"));
    assert(!mod_filename_matches("mod."));
    assert(!mod_filename_matches("song.mo"));
    assert(!mod_filename_matches("song.xm"));
    assert(!mod_filename_matches("amod.song"));
    assert(!mod_filename_matches("mod"));
    assert(!mod_filename_matches("dir/MOD."));
    assert(!mod_filename_matches(NULL));
    puts("PASS MOD filenames: suffix .MOD and Amiga prefix MOD.title");
    return 0;
}
