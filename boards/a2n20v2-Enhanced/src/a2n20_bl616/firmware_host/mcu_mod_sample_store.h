/* J2: external 4-channel MOD sample bytes in high FPGA SDRAM.
 * The CPU retains only the header and pattern table; cache misses fetch an
 * aligned SPI SPACE1 page into one of four per-voice MCU SRAM buffers.
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
#define MOD_STORE_PAGE      4096u
#define MOD_STORE_VOICES    4u

/* lengths are decoded PCM sample byte lengths, in MOD instrument order. */
bool mod_store_begin(const uint32_t lengths[31]);
uint32_t mod_store_size(void);
bool mod_store_stage(uint32_t offset,const uint8_t *data,uint16_t len);
void mod_store_invalidate(void);
uint32_t mod_store_faults(void);
uint32_t mod_store_misses(void);
mchar mod_store_read(void *unused,const mchar *virtual_base,
                     mulong byte_offset,unsigned voice);
void mod_store_write(void *unused,const mchar *virtual_base,
                     mulong byte_offset,mchar value);
#endif
