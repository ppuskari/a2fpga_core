/* J2R6: independent FPGA SDRAM pattern bank and MCU active-pattern cache.
 * FPGA has 8 MiB byte-addressed via SPI SPACE1. Samples occupy 0x400000-
 * 0x5fffff. This 256-KiB bank occupies 0x600000-0x63ffff; no overlap.
 * Max pattern payload: 128 patterns * 64 rows * 8 channels * 4B = 256 KiB.
 */
#ifndef MCU_MOD_PATTERN_STORE_H
#define MCU_MOD_PATTERN_STORE_H
#include <stdbool.h>
#include <stdint.h>
#include "third_party/hxcmod/hxcmod.h"

#define MOD_PATTERN_SDRAM_BASE     0x600000u
#define MOD_PATTERN_SDRAM_CAPACITY 0x040000u
#define MOD_PATTERN_CACHE_BYTES   (64u * 8u * 4u)

bool mod_patterns_begin(unsigned channels, unsigned pattern_count);
bool mod_patterns_stage(uint32_t offset, const uint8_t *data, uint16_t length);
bool mod_patterns_verify(uint32_t offset, const uint8_t *expected, uint16_t length);
/* HxCMOD callback: one whole pattern is cached; returns pointer to 64 rows
 * of note events. Pointer remains valid until a different pattern is fetched. */
note *mod_patterns_get(void *opaque, unsigned pattern, unsigned channels);
uint32_t mod_patterns_bytes(void);
uint32_t mod_patterns_fetch_count(void);
uint32_t mod_patterns_cache_hits(void);
uint32_t mod_patterns_read_bytes(void);
uint32_t mod_patterns_faults(void);
void mod_patterns_invalidate(void);
#endif
