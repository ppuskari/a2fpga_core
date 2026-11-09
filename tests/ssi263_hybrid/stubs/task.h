#ifndef TEST_TASK_H
#define TEST_TASK_H
#include <stdint.h>
#define taskENTER_CRITICAL() ((void)0)
#define taskEXIT_CRITICAL() ((void)0)
void vTaskDelay(uint32_t ticks);
void vTaskDelete(void *task);
#endif
