#ifndef P1D_FREERTOS_MOCK_H
#define P1D_FREERTOS_MOCK_H
#include <stdint.h>
#include <stddef.h>
void *pvPortMalloc(size_t size);
void vPortFree(void *p);
/* Host-only shim: test malloc path without a real FreeRTOS heap. */
static inline size_t xPortGetFreeHeapSize(void){ return 1024u*1024u; }
#define pdMS_TO_TICKS(ms) (ms)
#endif
