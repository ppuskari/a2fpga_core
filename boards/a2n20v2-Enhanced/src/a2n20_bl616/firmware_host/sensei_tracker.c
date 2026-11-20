/*
 * SenseiPlay8 P2AA: Native NinjaTrackerPlus only.
 *
 * No ProTracker player, sample conversion, synthetic tracker or MOD engine.
 * Keep the proven P2S lossless timestamped DOC register-event transport.
 * The original NTP file provides DOC-ready PCM, patterns and order table.
 * P2Y FPGA-assisted first-end sustain retarget is required.
 */
#include "sensei_tracker.h"
#include "sensei_ntp_native.h"
#include "sensei_runtime.h"
#include "sensei_pcm_upload.h"
#include "sensei_event_queue.h"
#include "fpga_spi.h"
#include "osd_console.h"
#include "FreeRTOS.h"
#include "task.h"
#include "usb_osal.h"
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#define TRACK_SPACE 6u
#define REG_STATE 0x05u
#define REG_FLUSH 0x15u
#define REG_OWNER 0x16u
#define REG_DIAG_CLEAR 0x17u
#define STATE_IDLE 0u
#define STATE_PLAY 2u
#define STATE_DONE 3u
#define STATE_ERROR 4u

typedef struct {
    uint8_t active,finishing,last_seq,audition_mode;
    sensei_ntp_player_t ntp;
    uint16_t time_finish;
} native_tracker_state_t;

/* One owner; all large state resides in static task-owned BSS. */
static native_tracker_state_t s;
static sensei_runtime_module_t user_ntp;
static sensei_event_queue_t g_doc_pending;

static void tracker_write(uint32_t addr,uint8_t data)
{
    fpga_spi_xfer_write(TRACK_SPACE,addr,&data,1);
}
static void tracker_read(uint8_t out[13])
{
    fpga_spi_xfer_read(TRACK_SPACE,0,out,13);
}
static void tracker_event(uint16_t when,uint8_t reg,uint8_t value)
{
    (void)sensei_queue_push(&g_doc_pending,when,reg,value);
}
static void tracker_event_send(uint16_t when,uint8_t reg,uint8_t data)
{
    const uint8_t packet[5] = {
        (uint8_t)when,(uint8_t)(when>>8),reg,data,0xA5u
    };
    fpga_spi_xfer_write(TRACK_SPACE,0x10,packet,sizeof packet);
}
static uint8_t tracker_fpga_level(void)
{
    uint8_t level=0xFFu;
    fpga_spi_xfer_read(TRACK_SPACE,0x06,&level,1);
    return level;
}
static void tracker_pump(uint16_t now)
{
    uint8_t level;
    if(!g_doc_pending.count)return;
    level=tracker_fpga_level();
    (void)sensei_queue_drain(&g_doc_pending,level,SENSEI_FPGA_FIFO_CAP,
                             now,SENSEI_FPGA_FIFO_CAP,tracker_event_send);
}
static void tracker_halt(uint16_t when,uint8_t osc)
{
    tracker_event(when,(uint8_t)(0x40u+osc),0u);
    tracker_event(when,(uint8_t)(0xA0u+osc),1u);
}
static void tracker_stop(uint16_t now,uint8_t state)
{
    uint8_t overflow=0u,stats[3]={0u};
    const uint32_t sent=g_doc_pending.emitted;
    const uint32_t late=g_doc_pending.late;
    const uint16_t high=g_doc_pending.high_water;
    const uint16_t maxlate=g_doc_pending.max_late_ms;
    fpga_spi_xfer_read(TRACK_SPACE,0x07,&overflow,1);
    fpga_spi_xfer_read(TRACK_SPACE,0x28,stats,3);
    osd_log("P2AA FPGA OVR=%u HIGH=%u LATE=%u",
            (unsigned)overflow,(unsigned)stats[0],
            (unsigned)((unsigned)stats[1]|((unsigned)stats[2]<<8)));
    osd_log("P2AA MCU SENT=%lu HIGH=%u",
            (unsigned long)sent,(unsigned)high);
    osd_log("P2AA MCU LATE=%lu MAXMS=%u",
            (unsigned long)late,(unsigned)maxlate);
    osd_log("P2AA NOTE CH0=%lu CH1=%lu",
            (unsigned long)s.ntp.note_starts[0],
            (unsigned long)s.ntp.note_starts[1]);
    osd_log("P2AA NOTE CH2=%lu CH3=%lu",
            (unsigned long)s.ntp.note_starts[2],
            (unsigned long)s.ntp.note_starts[3]);
    tracker_write(REG_FLUSH,0xA5u);
    sensei_queue_reset(&g_doc_pending);
    for(uint8_t ch=0;ch<8u;ch++)
        tracker_halt((uint16_t)(now+4u),ch);
    tracker_pump(now);
    vTaskDelay(pdMS_TO_TICKS(25));
    tracker_write(REG_OWNER,0u);
    tracker_write(REG_STATE,state);
    s.active=0u;s.finishing=0u;
    sensei_runtime_set_status(state==STATE_DONE ? SENSEI_RT_DONE :
                              state==STATE_ERROR ? SENSEI_RT_ERROR :
                              SENSEI_RT_IDLE);
}
static bool tracker_begin(uint16_t now)
{
    if(!user_ntp.file || !user_ntp.pcm || !user_ntp.order_count)
        return false;
    if(!sensei_ntp_init(&s.ntp,user_ntp.ntp_raw_patterns,
                        user_ntp.ntp_pattern_count,user_ntp.order_table,
                        user_ntp.order_count,user_ntp.catalog,
                        user_ntp.channel_pan,user_ntp.ntp_instrument_map,
                        user_ntp.ntp_irq_instruments,now))
        return false;
    s.audition_mode=sensei_runtime_audition_mode();
    switch(s.audition_mode) {
    case 1:s.ntp.audition_mask=0x01u;break;
    case 2:s.ntp.audition_mask=0x02u;break;
    case 3:s.ntp.audition_mask=0x04u;break;
    case 4:s.ntp.audition_mask=0x08u;break;
    case 5:s.ntp.audition_mask=0x06u;break;
    case 6:s.ntp.audition_mask=0x09u;break;
    default:s.ntp.audition_mask=0x0Fu;break;
    }
    sensei_queue_reset(&g_doc_pending);
    tracker_write(REG_FLUSH,0xA5u);
    tracker_write(REG_DIAG_CLEAR,0xA5u);
    tracker_write(REG_OWNER,1u);
    /* Configure DOC clock/active oscillator count before first score tick. */
    tracker_event((uint16_t)(now+4u),0xE1u,0x3Eu);
    for(uint8_t ch=0;ch<8u;ch++)
        tracker_halt((uint16_t)(now+4u),ch);
    tracker_write(REG_STATE,STATE_PLAY);
    s.active=1u;s.finishing=0u;
    sensei_runtime_set_status(SENSEI_RT_PLAYING);
    osd_log("SENSEI P2AC: NTP V%u PITCH ONLY",
            (unsigned)user_ntp.ntp_version);
    osd_log("SENSEI P2AA: MASK=%02X NONIDEAL=%u",
            (unsigned)s.ntp.audition_mask,
            (unsigned)user_ntp.ntp_nonideal);
    return true;
}
void sensei_tracker_task(void *unused)
{
    uint8_t st[13];
    char request[SENSEI_PATH_CAP];
    (void)unused;
    memset(&s,0,sizeof(s));
    s.last_seq=0xFFu;
    osd_log("SENSEI P2AA: NTP-ONLY 4K WORKER");
    for(;;) {
        bool just_started=false;
        uint16_t now;
        uint8_t seq,cmd,arg;
        tracker_read(st);
        if(!s.active && sensei_runtime_pending(request,sizeof request)) {
            uint8_t cap_pcm=0u,cap_ntp=0u;
            fpga_spi_xfer_read(TRACK_SPACE,0x26,&cap_pcm,1);
            fpga_spi_xfer_read(TRACK_SPACE,0x2B,&cap_ntp,1);
            if(st[0]!=0x53u || st[1]!=0x1Du ||
               !(st[12]&1u) || cap_pcm!=0x42u || cap_ntp!=0x59u) {
                sensei_runtime_set_status(SENSEI_RT_ERROR);
                osd_log("P2AA: NEED P2Y FPGA + NATIVE DOC");
            } else {
                sensei_runtime_free(&user_ntp);
                osd_log("P2AA: LOADING NTP FILE");
                if(!sensei_runtime_load(request,&user_ntp)) {
                    osd_log("P2AA: NTP LOAD/PARSE FAILED");
                } else {
                    osd_log("P2AA: PCM %lu BYTES; BEGIN DMA",
                            (unsigned long)user_ntp.pcm_length);
                    tracker_write(REG_STATE,5u); /* LOADING */
                    sensei_runtime_set_status(SENSEI_RT_LOADING);
                    if(!sensei_pcm_upload(user_ntp.pcm,user_ntp.pcm_length)) {
                        tracker_write(REG_STATE,STATE_ERROR);
                        sensei_runtime_set_status(SENSEI_RT_ERROR);
                        osd_log("P2AA: DOC PCM DMA FAILED");
                    } else {
                        osd_log("P2AA: DOC PCM DMA VERIFIED");
                        tracker_read(st);
                        now=(uint16_t)st[8]|((uint16_t)st[9]<<8);
                        just_started=tracker_begin(now);
                        if(!just_started) {
                            tracker_write(REG_STATE,STATE_ERROR);
                            sensei_runtime_set_status(SENSEI_RT_ERROR);
                            osd_log("P2AA: NTP START FAILED");
                        }
                        tracker_read(st);
                    }
                }
            }
        }
        if(st[0]!=0x53u || st[1]!=0x1Du || !(st[12]&1u)) {
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;
        }
        seq=st[3];cmd=st[2];arg=st[4];
        now=(uint16_t)st[8]|((uint16_t)st[9]<<8);
        if(seq!=s.last_seq) {
            s.last_seq=seq;
            if(cmd==2u && s.active)tracker_stop(now,STATE_IDLE);
            else if(cmd==1u && !s.active) {
                if(arg==3u)tracker_write(REG_STATE,STATE_IDLE);
                else {
                    /* Obsolete P1D/P1E synthetic songs intentionally gone. */
                    tracker_write(REG_STATE,STATE_ERROR);
                    osd_log("P2AA: USE NTP FILE PICKER");
                }
            }
        }
        if(sensei_runtime_take_stop_request() && s.active)
            tracker_stop(now,STATE_IDLE);
        if(s.active && !just_started && !(st[12]&0x02u)) {
            s.active=0u;s.finishing=0u;
            sensei_queue_reset(&g_doc_pending);
            tracker_write(REG_STATE,STATE_IDLE);
            sensei_runtime_set_status(SENSEI_RT_ERROR);
            osd_log("P2AA: DOC OWNERSHIP LOST");
        }
        if(s.active) {
            tracker_pump(now);
            if(!sensei_ntp_done(&s.ntp) &&
               g_doc_pending.count<=SENSEI_EVENT_CAP-SENSEI_MAX_TICK_EVENTS &&
               (int16_t)((uint16_t)(now+160u)-
                         sensei_ntp_next_ms(&s.ntp))>=0) {
                (void)sensei_ntp_tick(&s.ntp,tracker_event);
                tracker_pump(now);
            }
            if(g_doc_pending.failed) {
                osd_log("P2AA: MCU EVENT STAGING OVERFLOW");
                tracker_stop(now,STATE_ERROR);
            } else {
                if(sensei_ntp_done(&s.ntp) && !s.finishing) {
                    s.finishing=1u;
                    s.time_finish=(uint16_t)(sensei_ntp_next_ms(&s.ntp)+25u);
                }
                if(s.finishing && !g_doc_pending.count &&
                   tracker_fpga_level()==0u &&
                   (int16_t)(now-s.time_finish)>=0) {
                    tracker_stop(now,STATE_DONE);
                    osd_log("P2AA: NTP PLAYBACK DONE");
                }
            }
        }
        vTaskDelay(pdMS_TO_TICKS(5));
    }
}
