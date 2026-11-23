#ifndef M3_FATFS_MTIMER_H
#define M3_FATFS_MTIMER_H
#include <stdint.h>
uint64_t bflb_mtimer_get_time_us(void);
void bflb_mtimer_delay_us(uint32_t us);
#endif
