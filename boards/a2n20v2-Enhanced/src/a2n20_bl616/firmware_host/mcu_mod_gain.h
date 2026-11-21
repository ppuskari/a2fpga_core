/* J2R3 independent post-HxCMOD stereo PCM gain stage.
 * Applies before existing SPI SPACE6 PCM FIFO: no FPGA HDL changes.
 * Gain changes live, 0..12 dB (default +8 dB); linked stereo peak
 * limiter holds sample peaks <= -2.0 dBFS. Original PCM 44.1k/16-bit.
 */
#ifndef MCU_MOD_GAIN_H
#define MCU_MOD_GAIN_H
#include <stdint.h>
#define MOD_GAIN_DEFAULT_DB 8u
#define MOD_GAIN_MAX_DB 12u
#define MOD_GAIN_CEILING 26028 /* signed 16-bit -2 dBFS sample peak */
void mod_gain_set_db(unsigned db);
unsigned mod_gain_get_db(void);
void mod_gain_reset(void);
void mod_gain_apply(int16_t *stereo_pcm,unsigned frames);
#endif
