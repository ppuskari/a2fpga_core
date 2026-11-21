#ifndef P1D_TASK_MOCK_H
#define P1D_TASK_MOCK_H
#include <stdint.h>
typedef void *TaskHandle_t;
static inline TaskHandle_t xTaskGetCurrentTaskHandle(void){ return (TaskHandle_t)(uintptr_t)1u; }
void vTaskDelay(uint32_t ticks);
#endif
