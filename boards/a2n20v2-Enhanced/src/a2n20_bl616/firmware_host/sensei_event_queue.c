#include "sensei_event_queue.h"
#include <string.h>
void sensei_queue_reset(sensei_event_queue_t *q) { memset(q,0,sizeof(*q)); }
bool sensei_queue_push(sensei_event_queue_t *q,uint16_t when,uint8_t reg,uint8_t data)
{
    if(q->count>=SENSEI_EVENT_CAP) {q->failed++;return false;}
    unsigned pos=((unsigned)q->head+q->count)%SENSEI_EVENT_CAP;
    q->event[pos]=(sensei_event_t){when,reg,data};
    ++q->count;
    ++q->accepted;
    if(q->count>q->high_water)q->high_water=q->count;
    return true;
}
unsigned sensei_queue_drain(sensei_event_queue_t *q,unsigned fpga_level,
    unsigned fpga_capacity,uint16_t now,unsigned max_writes,sensei_event_sink_t sink)
{
    unsigned sent=0;
    if(!sink || !fpga_capacity || fpga_capacity>255u ||
       fpga_level>fpga_capacity)return 0;
    // The MCU is the only SPI6 event producer. Consumer activity can only
    // increase free space after this snapshot, never decrease it.
    unsigned space=fpga_capacity-fpga_level;
    if(space>max_writes)space=max_writes;
    while(sent<space && q->count) {
        const sensei_event_t e=q->event[q->head];
        int16_t delta=(int16_t)(now-e.when);
        if(delta>0) {
            ++q->late;
            if((uint16_t)delta>q->max_late_ms)
                q->max_late_ms=(uint16_t)delta;
        }
        sink(e.when,e.reg,e.data);
        q->head=(uint16_t)((q->head+1u)%SENSEI_EVENT_CAP);
        --q->count;
        ++q->emitted;
        ++sent;
    }
    return sent;
}
