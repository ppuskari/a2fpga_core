#ifndef SENSEI_PCM_UPLOAD_H
#define SENSEI_PCM_UPLOAD_H
#include <stdbool.h>
#include <stdint.h>

/* BL616 -> SPI6 -> FPGA GLU SDRAM, P2 acknowledged 32-bit word uploads.
 * Blocks until every word is acknowledged or fails/times out.
 * No DOC playback is possible during upload. */
bool sensei_pcm_upload(const uint8_t *pcm, uint32_t bytes);
#endif
