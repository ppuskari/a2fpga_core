#ifndef SENSEI_EVENT_QUEUE_H
#define SENSEI_EVENT_QUEUE_H
/* P2S: bounded MCU staging queue for timestamped Ensoniq DOC writes.
 * One producer (the BL616 tracker task); no song/event precomputation.
 * FPGA remains the source of truth for occupancy and executes timestamps.
 */
#include <stdbool.h>
#include <stdint.h>
#define SENSEI_EVENT_CAP 256u
#define SENSEI_FPGA_FIFO_CAP 64u
#define SENSEI_MAX_TICK_EVENTS 64u
typedef struct {
    uint16_t when;
    uint8_t reg, data;
} sensei_event_t;
typedef struct {
    sensei_event_t event[SENSEI_EVENT_CAP];
    uint16_t head, count, high_water;
    uint32_t accepted, emitted, late, failed;
    uint16_t max_late_ms;
} sensei_event_queue_t;
typedef void (*sensei_event_sink_t)(uint16_t when,uint8_t reg,uint8_t data);
void sensei_queue_reset(sensei_event_queue_t *q);
bool sensei_queue_push(sensei_event_queue_t *q,uint16_t when,uint8_t reg,uint8_t data);
unsigned sensei_queue_drain(sensei_event_queue_t *q,unsigned fpga_level,
    unsigned fpga_capacity,uint16_t now,unsigned max_writes,sensei_event_sink_t sink);
#endif
