#ifndef J2R9_MTIMER_MOCK_H
#define J2R9_MTIMER_MOCK_H
#include <stdint.h>
uint64_t bflb_mtimer_get_time_ms(void);
void bflb_mtimer_delay_ms(uint32_t ms);
void bflb_mtimer_delay_us(uint32_t us);
#endif
