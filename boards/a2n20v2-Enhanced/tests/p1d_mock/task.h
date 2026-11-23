#ifndef P1D_TASK_MOCK_H
#define P1D_TASK_MOCK_H
void vTaskDelay(uint32_t ticks);
void vTaskSuspendAll(void);
int xTaskResumeAll(void);
void taskYIELD(void);
#endif
