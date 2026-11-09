#ifndef TEST_TASK_H
#define TEST_TASK_H
#include <stdint.h>
void vTaskDelay(uint32_t ticks);
void vTaskDelete(void *task);
#endif
