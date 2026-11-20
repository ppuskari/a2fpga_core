/*
 * SenseiPlay8 P1D -- BL616 real-time four-voice tracker demonstration.
 *
 * IIe performs ONLY the initial 1 KiB sample upload and sends a mailbox
 * START. Subsequent tracker tick computation is handled here, while the
 * FPGA's 1ms timer executes timestamped DOC writes independently of USB,
 * disk serving, and 6502 timing. No direct DOC writes from the MCU.
 *
 * The first integration deliberately uses the original P0P8 four-wavetable
 * bank (sine/triangle/pulse/bell, eight cycles per 256 bytes). Arbitrary
 * MOD loading and MCU-to-DOC sample DMA are next milestones, not implied
 * by this first demo. It is NEVER enabled outside native DOC mode.
 *
 * Copyright (c) 2026 Petar Puskarich and contributors.
 */
#include "sensei_tracker.h"
#include "sensei_mod_player.h"
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

#define TRACK_SPACE 6
#define REG_STATE  0x05
#define REG_FLUSH  0x15
#define REG_OWNER  0x16
#define STATE_IDLE  0
#define STATE_PLAY  2
#define STATE_DONE  3
#define STATE_ERROR 4
#define SONG_ROWS  192u
#define REG_DIAG_CLEAR 0x17u
// The hardware FIFO is 64 events. The MCU stages a complete ProTracker
// tick separately, then sends only the slots the FPGA reports as free.
// The previous `level<=24` check could submit 56 notes into 40 slots.
static sensei_event_queue_t g_doc_pending;

typedef struct {
    uint8_t active;
    uint8_t last_seq;
    uint8_t finishing;
    uint8_t real_mod;
    uint8_t audition_mode;
    uint8_t native_ntp;  /* raw NTP score, not P2U encoded MOD patterns */
    sensei_mod_player_t mod;
    sensei_ntp_player_t ntp;
    uint16_t time_next;
    uint16_t time_finish;
    uint16_t row;
    uint8_t tick;
    uint16_t base_fc[4];
    uint8_t vol[4];
} tracker_state;

static const uint16_t pitch_period[4][8] = {
    {428,381,339,320,285,254,226,214},
    {571,508,453,428,381,339,302,285},
    {856,762,678,640,570,508,453,428},
    {214,226,254,285,320,339,381,428}
};
/* 2^semitone/12 in signed Q11, 0..7 semitones. */
static const uint16_t arp_q11[8] = {
    2048,2166,2300,2434,2580,2734,2897,3070
};
static const int8_t vib_wave[16] = {
    0,2,4,5,6,5,4,2,0,-2,-4,-5,-6,-5,-4,-2
};

static void tracker_write(uint32_t addr, uint8_t data)
{
    fpga_spi_xfer_write(TRACK_SPACE, addr, &data, 1);
}

static void tracker_read(uint8_t status[13])
{
    fpga_spi_xfer_read(TRACK_SPACE, 0, status, 13);
}

/* The tracker computes events in ProTracker tick order; the MCU queues
 * them atomically before transport. No 5-byte SPI writes in callbacks. */
static void tracker_event(uint16_t when, uint8_t doc_reg, uint8_t value)
{
    (void)sensei_queue_push(&g_doc_pending,when,doc_reg,value);
}
static void tracker_event_send(uint16_t when,uint8_t reg,uint8_t value)
{
    const uint8_t packet[5]={
        (uint8_t)when,(uint8_t)(when>>8),reg,value,0xA5
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
    if(!g_doc_pending.count)return;
    const uint8_t level=tracker_fpga_level();
    // Occupancy is sampled before this single-producer batch. Concurrent
    // DOC consumption only adds free slots; no other SPI6 producer pushes.
    (void)sensei_queue_drain(&g_doc_pending,level,SENSEI_FPGA_FIFO_CAP,
                            now,SENSEI_FPGA_FIFO_CAP,tracker_event_send);
}

static uint16_t period_to_fc(uint16_t period)
{
    /* Same 32-DOC-oscillator 7.159 MHz sample-rate conversion as the PC
     * converter, rounded to nearest integer, without floating point. */
    const uint32_t numerator = 69013u;
    return (uint16_t)((numerator + period/2u) / period);
}

static uint16_t transpose_fc(uint16_t fc, unsigned semitones)
{
    return (uint16_t)(((uint32_t)fc * arp_q11[semitones & 7u] + 1024u)>>11);
}

static void tracker_halt(uint16_t when, uint8_t channel)
{
    tracker_event(when, (uint8_t)(0x40u + channel), 0);
    tracker_event(when, (uint8_t)(0xA0u + channel), 1);
}

static void tracker_start_voice(uint16_t when, unsigned channel, uint16_t fc, uint8_t vol)
{
    uint8_t ch = (uint8_t)channel;
    uint8_t control = (ch == 1 || ch == 2) ? 0x10 : 0x00;
    /* 256-byte loop per instrument at pages 0,1,2,3; RTC/WTS=0. */
    tracker_event(when, (uint8_t)(0xA0u+ch), (uint8_t)(control|1u));
    tracker_event(when, (uint8_t)(0x80u+ch), ch);
    tracker_event(when, (uint8_t)(0xC0u+ch), 0);
    tracker_event(when, ch, (uint8_t)fc);
    tracker_event(when, (uint8_t)(0x20u+ch), (uint8_t)(fc>>8));
    tracker_event(when, (uint8_t)(0x40u+ch), vol);
    tracker_event(when, (uint8_t)(0xA0u+ch), control);
}

static void tracker_pitch(uint16_t when, uint8_t ch, uint16_t fc)
{
    tracker_event(when, ch, (uint8_t)fc);
    tracker_event(when, (uint8_t)(0x20u+ch), (uint8_t)(fc>>8));
}

/* All calculations happen on the BL616 at ~20ms ProTracker tick cadence.
 * The FPGA subsequently executes each DOC write at 'when' independently. */
static void tracker_emit_tick(tracker_state *s)
{
    unsigned ch;
    uint8_t tick = s->tick;
    uint16_t when = s->time_next;
    if (tick == 0) {
        for (ch=0; ch<4; ++ch) {
            bool trigger = (ch==2) ? (s->row%8u==0) : (s->row%4u==0);
            if (trigger) {
                unsigned index = (s->row/4u + (s->row/64u)*(ch+1u)) % 8u;
                s->base_fc[ch] = period_to_fc(pitch_period[ch][index]);
                s->vol[ch] = (uint8_t)(ch==2 ? 112 : 144);
                tracker_start_voice(when, ch, s->base_fc[ch], s->vol[ch]);
            }
        }
    } else {
        /* Arpeggio 0xy on ch0, x=4 y=7. Compute the pitch NOW, not offline. */
        uint8_t semitone = (tick%3u==1u) ? 4u : (tick%3u==2u ? 7u : 0u);
        tracker_pitch(when, 0, transpose_fc(s->base_fc[0], semitone));

        /* Ch3 vibrato at two DOC FC steps per quarter-wave. */
        uint8_t phase = (uint8_t)((s->row*6u+tick)&15u);
        tracker_pitch(when, 3, (uint16_t)(s->base_fc[3]+vib_wave[phase]));

        /* Ch1 volume slide: fade/recover six ticks within each row. */
        s->vol[1] = (uint8_t)(144u - tick*6u);
        tracker_event(when, 0x41, s->vol[1]);
    }
    s->time_next = (uint16_t)(s->time_next+20u);
    ++s->tick;
    if (s->tick==6) {
        s->tick=0;
        ++s->row;
    }
}

/* Both players share the proven FPGA-millisecond event transport. They do
 * NOT share a score/effect interpreter or a DOC instrument state machine. */
static bool song_done(const tracker_state *s)
{
    return s->native_ntp ? sensei_ntp_done(&s->ntp) :
           sensei_mod_done(&s->mod);
}
static uint16_t song_next(const tracker_state *s)
{
    return s->native_ntp ? sensei_ntp_next_ms(&s->ntp) :
           sensei_mod_next_ms(&s->mod);
}
static void song_tick(tracker_state *s)
{
    if(s->native_ntp) (void)sensei_ntp_tick(&s->ntp,tracker_event);
    else (void)sensei_mod_tick(&s->mod,tracker_event);
}

static void tracker_stop(tracker_state *s, uint16_t now, uint8_t state)
{
    unsigned ch;
    if(s->real_mod==2u) {
        uint8_t overflow=0, stats[3]={0};
        fpga_spi_xfer_read(TRACK_SPACE,0x07,&overflow,1);
        fpga_spi_xfer_read(TRACK_SPACE,0x28,stats,3);
        const unsigned late_hw=(unsigned)stats[1]|((unsigned)stats[2]<<8);
        /* Console is 39 columns. Split diagnostics rather than
         * silently truncating the evidence needed for audio analysis. */
        osd_log("P2U FPGA OVR=%u HIGH=%u LATE=%u",
                (unsigned)overflow,(unsigned)stats[0],late_hw);
        osd_log("P2U MCU SENT=%lu HIGH=%u",
                (unsigned long)g_doc_pending.emitted,
                (unsigned)g_doc_pending.high_water);
        osd_log("P2U MCU LATE=%lu MAXMS=%u",
                (unsigned long)g_doc_pending.late,
                (unsigned)g_doc_pending.max_late_ms);
        osd_log("P2U NOTES CH0=%lu CH1=%lu",
                (unsigned long)(s->native_ntp?s->ntp.note_starts[0]:s->mod.note_starts[0]),
                (unsigned long)(s->native_ntp?s->ntp.note_starts[1]:s->mod.note_starts[1]));
        osd_log("P2U NOTES CH2=%lu CH3=%lu",
                (unsigned long)(s->native_ntp?s->ntp.note_starts[2]:s->mod.note_starts[2]),
                (unsigned long)(s->native_ntp?s->ntp.note_starts[3]:s->mod.note_starts[3]));
        osd_log("P2U AUDITION=%u MASK=%02X",
                (unsigned)s->audition_mode,
                (unsigned)(s->native_ntp?s->ntp.audition_mask:s->mod.audition_mask));
    }
    /* Drop stale future events, mute the owned DOC at a near-future deadline,
     * then release owner only AFTER these writes have been executed. */
    tracker_write(REG_FLUSH, 0xA5);
    // Drop all outstanding MCU events from the previous song before STOP.
    sensei_queue_reset(&g_doc_pending);
    // Runtime ProTracker uses four PAIRS: DOC 0/1,2/3,4/5,6/7.
    // Stop all eight physical oscillators so sustain partners cannot
    // continue after STOP, end-of-song or the next MOD selection.
    for (ch=0; ch<(s->real_mod==2u?8u:4u); ++ch)
        tracker_halt((uint16_t)(now+4u), (uint8_t)ch);
    tracker_pump(now);
    vTaskDelay(pdMS_TO_TICKS(25));
    tracker_write(REG_OWNER, 0);
    tracker_write(REG_STATE, state);
    s->active=0;
    s->finishing=0;
    if (s->real_mod==2u)
        sensei_runtime_set_status(state==STATE_DONE ?
                                  SENSEI_RT_DONE : SENSEI_RT_IDLE);
}

static bool tracker_begin(tracker_state *s, uint16_t now, uint8_t song_id)
{
    memset(s->base_fc,0,sizeof s->base_fc);
    memset(s->vol,0,sizeof s->vol);
    s->row=0;
    s->tick=0;
    s->real_mod=(song_id==1 || song_id==2) ? 1u : 0u;
    s->native_ntp=0u; /* legacy/P1E demo never routes through NTP engine */
    if (s->real_mod && !sensei_mod_init(&s->mod,song_id,now)) {
        tracker_write(REG_STATE, STATE_ERROR);
        return false;
    }
    s->time_next=(uint16_t)(now+100u);
    s->active=1;
    s->finishing=0;
    sensei_queue_reset(&g_doc_pending);
    tracker_write(REG_FLUSH, 0xA5);
    tracker_write(REG_DIAG_CLEAR, 0xA5);
    tracker_write(REG_OWNER, 1);
    tracker_write(REG_STATE, STATE_PLAY);
    osd_log(s->real_mod ? "SENSEI P1E: REAL MOD START" :
           "SENSEI P1D: MCU/FPGA TRACKER START");
    return true;
}

/* Runtime source: no per-song firmware compilation. PCM must have been
 * written and ACKed to DOC sound RAM before any oscillator can start. */
static bool tracker_begin_runtime(tracker_state *s,
                                  sensei_runtime_module_t *module,
                                  uint16_t now)
{
    if (!module || !module->file || !module->pcm || !module->order_count)
        return false;
    s->native_ntp=module->source_ntp;
    if(s->native_ntp) {
        /* Raw NTP pattern bytes, original per-track DOC routing and
         * waveform-end IRQ pairing: NO ProTracker interpreter call. */
        if(!sensei_ntp_init(&s->ntp,module->ntp_raw_patterns,
                            module->ntp_pattern_count,module->order_table,
                            module->order_count,module->catalog,
                            module->channel_pan,module->ntp_instrument_map,
                            module->ntp_irq_instruments,now))
            return false;
    } else if(!sensei_mod_init_runtime(&s->mod,module->song.rows,
                                      module->order_table,module->order_count,
                                      module->catalog,now))
        return false;
    s->mod.audition_mask=0x0fu;
    s->real_mod=2u;
    s->audition_mode=sensei_runtime_audition_mode();
    /* All four tracker channels continue to execute effect and global
     * flow logic. Only their output register events are selectively
     * disabled, for isolated speaker/instrument A/B tests. */
    switch (s->audition_mode) {
    case 1: s->mod.audition_mask=0x01u;break;
    case 2: s->mod.audition_mask=0x02u;break;
    case 3: s->mod.audition_mask=0x04u;break;
    case 4: s->mod.audition_mask=0x08u;break;
    case 5: s->mod.audition_mask=0x06u;break;
    case 6: s->mod.audition_mask=0x09u;break;
    default:s->mod.audition_mask=0x0Fu;break;
    }
    if(s->native_ntp)
        s->ntp.audition_mask=s->mod.audition_mask;
    s->active=1;
    s->finishing=0;
    sensei_queue_reset(&g_doc_pending);
    tracker_write(REG_FLUSH,0xA5);
    tracker_write(REG_DIAG_CLEAR,0xA5);
    tracker_write(REG_OWNER,1);
    // P0 uses E1=$3E (32 oscillators) for the established
    // FC=69013/period conversion. Generic P2 ProDOS skips P0 InitDOC,
    // so explicitly restore that timing and halt both sides of all
    // four attack/sustain pairs before starting the first MOD row.
    tracker_event((uint16_t)(now+4u),0xE1,0x3E);
    for(unsigned ch=0;ch<8u;ch++)
        tracker_halt((uint16_t)(now+4u),(uint8_t)ch);
    tracker_write(REG_STATE,STATE_PLAY);
    sensei_runtime_set_status(SENSEI_RT_PLAYING);
    if(module->source_ntp)
        osd_log("SENSEI P2Y: NTP V%u NATIVE C/FPGA",
                (unsigned)module->ntp_version);
    else
        osd_log("SENSEI P2Y: ORIGINAL MOD P2U");
    osd_log("SENSEI P2Y: PLAY MASK=%02X",
            (unsigned)(s->native_ntp?s->ntp.audition_mask:s->mod.audition_mask));
    if(module->source_ntp && module->ntp_nonideal)
        osd_log("P2V NTP NONIDEAL LOOPS=%u",
                (unsigned)module->ntp_nonideal);
    return true;
}

void sensei_tracker_task(void *unused)
{
    uint8_t st[13];
    /* P2Z: BL616 Sensei task has only 3072 bytes of stack. P2Y added
     * the native NTP state alongside the existing MOD state; allocating
     * both in this task frame leaves too little room for the nested
     * FAT load -> format parser call chain. Single Sensei worker owns it. */
    static tracker_state s;
    static sensei_runtime_module_t user_mod;
    char requested_mod[SENSEI_PATH_CAP];
    (void)unused;
    memset(&s,0,sizeof s);
    s.last_seq=0xFF;
    osd_log("SENSEI P2Z: STATIC TRACKER STATE");

    for (;;) {
        uint16_t now;
        uint8_t seq,cmd,arg;
        bool just_started=false;
        tracker_read(st);
        // The menu chooses a normal .MOD file from USB/SD; all parsing,
        // sample conversion, upload and tick effects occur at runtime.
        // First verify Native DOC + the new FPGA PCM-DMA capability.
        if (!s.active && sensei_runtime_pending(requested_mod,
                                                sizeof requested_mod)) {
            uint8_t capability=0;
            fpga_spi_xfer_read(TRACK_SPACE,0x26,&capability,1);
            sensei_runtime_free(&user_mod);
            if (st[0]!=0x53 || st[1]!=0x1D || !(st[12]&1u) ||
                capability!=0x42) {
                sensei_runtime_set_status(SENSEI_RT_ERROR);
                osd_log("SENSEI P2: NEED NATIVE DOC AND P2 FPGA");
            } else if ((osd_log("SENSEI P2Z: FAT FILE LOAD"),
                        !sensei_runtime_load(requested_mod,&user_mod))) {
                osd_log("SENSEI P2V: BAD MOD/NTP OR UNSUPPORTED");
            } else {
                uint8_t ntp_assist_cap=0u;
                if(user_mod.source_ntp)
                    fpga_spi_xfer_read(TRACK_SPACE,0x2Bu,&ntp_assist_cap,1);
                if(user_mod.source_ntp && ntp_assist_cap!=0x59u) {
                    /* Do not run native NTP IRQ|SWAP on a P2S/P2W FPGA.
                     * The original head would restart instead of being
                     * retargeted to its sustain wave after first end. */
                    tracker_write(REG_STATE,STATE_ERROR);
                    sensei_runtime_set_status(SENSEI_RT_ERROR);
                    osd_log("SENSEI P2Y: REQUIRES P2Y FPGA");
                } else {
                osd_log("SENSEI P2Z: PCM SIZE=%lu",
                        (unsigned long)user_mod.pcm_length);
                tracker_write(REG_STATE,5); /* LOADING SAMPLES */
                sensei_runtime_set_status(SENSEI_RT_LOADING);
                if (!sensei_pcm_upload(user_mod.pcm,user_mod.pcm_length)) {
                    tracker_write(REG_STATE,STATE_ERROR);
                    sensei_runtime_set_status(SENSEI_RT_ERROR);
                    osd_log("SENSEI P2: DOC PCM UPLOAD FAILED");
                } else {
                    osd_log("SENSEI P2Z: DOC PCM DMA VERIFIED");
                    // Re-read FPGA time because upload may take seconds.
                    tracker_read(st);
                    uint16_t start_time=(uint16_t)st[8] |
                                         ((uint16_t)st[9]<<8);
                    just_started=tracker_begin_runtime(&s,&user_mod,
                                                        start_time);
                    if (!just_started) {
                        tracker_write(REG_STATE,STATE_ERROR);
                        sensei_runtime_set_status(SENSEI_RT_ERROR);
                    }
                    tracker_read(st);
                }
                }
            }
        }
        if (st[0]!=0x53 || st[1]!=0x1D || !(st[12]&1u)) {
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;  /* old FPGA, disabled personality or not configured */
        }
        seq=st[3]; cmd=st[2]; arg=st[4];
        now=(uint16_t)((uint16_t)st[8] | ((uint16_t)st[9]<<8));
        if (seq!=s.last_seq) {
            s.last_seq=seq;
            if (cmd==2 && s.active) {
                tracker_stop(&s,now,STATE_IDLE);
            } else if (cmd==1 && !s.active) {
                if (arg<=2) {
                    just_started=tracker_begin(&s,now,arg);
                } else if (arg==3) {
                    // Generic P2 ProDOS front-end arms the MOD picker.
                    // Files and samples are never compiled into the SYS.
                    tracker_write(REG_STATE,STATE_IDLE);
                } else tracker_write(REG_STATE,STATE_ERROR);
            }
        }
        if (sensei_runtime_take_stop_request() && s.active) {
            tracker_stop(&s,now,STATE_IDLE);
        }
        if (s.active && !just_started && !(st[12] & 0x02u)) {
            /* A2 reset, audio-mode change, or IIe C0CF panic revoked
             * FPGA ownership: immediately stop sending timed events. */
            s.active=0;
            s.finishing=0;
            tracker_write(REG_STATE, STATE_IDLE);
            if(s.real_mod==2u)
                sensei_runtime_set_status(SENSEI_RT_ERROR);
        }
        if (s.active) {
            /* Drain prior work first. The FPGA is the source of truth
             * for free slots, not a guessed upper bound on tick size. */
            tracker_pump(now);
            /* 160 ms lookahead helps multi-register DOC note setup.
             * Never generate a tick unless its worst-case 64 DOC writes
             * fit in the MCU's 256-event staging queue. We do not
             * advance the ProTracker tick until it is safely staged. */
            if ((s.real_mod ? !song_done(&s) : s.row<SONG_ROWS) &&
                g_doc_pending.count<=SENSEI_EVENT_CAP-SENSEI_MAX_TICK_EVENTS &&
                (int16_t)((uint16_t)(now+160u)-
                           (s.real_mod ? song_next(&s) :
                                         s.time_next))>=0) {
                if (s.real_mod) song_tick(&s);
                else tracker_emit_tick(&s);
                tracker_pump(now);
            }
            if (g_doc_pending.failed) {
                osd_log("SENSEI P2S: MCU STAGING OVERFLOW");
                tracker_stop(&s,now,STATE_ERROR);
                sensei_runtime_set_status(SENSEI_RT_ERROR);
            } else {
                if ((s.real_mod ? song_done(&s) : s.row==SONG_ROWS) &&
                    !s.finishing) {
                    s.finishing=1;
                    s.time_finish=(uint16_t)((s.real_mod ?
                            song_next(&s) : s.time_next)+25u);
                }
                if (s.finishing && !g_doc_pending.count &&
                    tracker_fpga_level()==0u &&
                    (int16_t)(now-s.time_finish)>=0) {
                    const uint32_t sent=g_doc_pending.emitted;
                    const uint16_t high=g_doc_pending.high_water;
                    const uint32_t late=g_doc_pending.late;
                    const uint16_t maxlate=g_doc_pending.max_late_ms;
                    tracker_stop(&s,now,STATE_DONE);
                    osd_log("SENSEI P2S: EVENTS=%lu HIGH=%u LATE=%lu MAXMS=%u",
                        (unsigned long)sent,(unsigned)high,
                        (unsigned long)late,(unsigned)maxlate);
                    osd_log(s.real_mod==2u ? (s.native_ntp ?
                            "SENSEI P2Y: NATIVE NTP DONE" :
                            "SENSEI P2S: RUNTIME MOD DONE") :
                            s.real_mod ? "SENSEI P1E: REAL MOD DONE" :
                            "SENSEI P1D: DONE 192 ROWS");
                }
            }
        }
        vTaskDelay(pdMS_TO_TICKS(5));
    }
}
