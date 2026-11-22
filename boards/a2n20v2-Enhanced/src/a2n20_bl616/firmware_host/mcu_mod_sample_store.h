/* J2R3: external 1..8 channel MOD sample bytes in high FPGA SDRAM.
 * The CPU retains only the 8-KiB shared pattern cache; PCM sample misses fetch
 * an aligned SPI SPACE1 page into one of eight per-voice MCU SRAM buffers.
 * Region [0x400000,0x600000) is reserved exclusively for MOD sample bytes.
 * Do not overlap SHADOW/DOC/DiskII/HDD or future SDRAM allocations.
 */
#ifndef MCU_MOD_SAMPLE_STORE_H
#define MCU_MOD_SAMPLE_STORE_H
#include <stdint.h>
#include <stdbool.h>
#include "third_party/hxcmod/hxcmod.h"

#define MOD_SDRAM_BASE      0x400000u
#define MOD_SDRAM_CAPACITY  0x200000u  /* 2 MiB */
/* J2R8: default to eight 8-KiB independent per-voice PCM sample pages.
 * For A/B comparison, -DMOD_STORE_PAGE=4096 restores the old 4-KiB pages.
 * Never use this define for FPGA staging limits or SDRAM address capacity. */
#ifndef MOD_STORE_PAGE
#define MOD_STORE_PAGE      8192u
#endif
#if MOD_STORE_PAGE != 8192u && MOD_STORE_PAGE != 4096u
#error "MOD_STORE_PAGE must be 8192 or 4096"
#endif
#define MOD_STORE_VOICES    8u

/* lengths are decoded PCM sample byte lengths, in MOD instrument order. */
bool mod_store_begin(const uint32_t lengths[31]);
uint32_t mod_store_size(void);
bool mod_store_stage(uint32_t offset,const uint8_t *data,uint16_t len);
/* Verify small sentinels after staging to catch unavailable/aliased SDRAM. */
bool mod_store_verify(uint32_t offset,const uint8_t *expected,uint16_t len);
void mod_store_invalidate(void);
uint32_t mod_store_faults(void);
uint32_t mod_store_misses(void);
uint32_t mod_store_read_bytes(void);
mchar mod_store_read(void *unused,const mchar *virtual_base,
                     mulong byte_offset,unsigned voice);
void mod_store_write(void *unused,const mchar *virtual_base,
                     mulong byte_offset,mchar value);
#endif
