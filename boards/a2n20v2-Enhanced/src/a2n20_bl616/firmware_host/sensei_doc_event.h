#ifndef SENSEI_DOC_EVENT_H
#define SENSEI_DOC_EVENT_H
#include <stdint.h>
/* Native NTP engine -> timestamped DOC register FIFO. No MOD dependency. */
typedef void (*sensei_doc_event_t)(uint16_t when,uint8_t reg,uint8_t data);
#endif
