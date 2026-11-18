#ifndef P1D_FREERTOS_MOCK_H
#define P1D_FREERTOS_MOCK_H
#include <stdint.h>
#include <stddef.h>
void *pvPortMalloc(size_t size);
void vPortFree(void *p);
#define pdMS_TO_TICKS(ms) (ms)
#endif
