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
#define FIFO_SAFE_LEVEL 24u /* largest tick burst <=35 in a 64-entry FIFO */

typedef struct {
    uint8_t active;
    uint8_t last_seq;
    uint8_t finishing;
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

static void tracker_event(uint16_t when, uint8_t doc_reg, uint8_t value)
{
    const uint8_t packet[5] = {
        (uint8_t)when, (uint8_t)(when >> 8), doc_reg, value, 0xA5
    };
    fpga_spi_xfer_write(TRACK_SPACE, 0x10, packet, sizeof packet);
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

static void tracker_stop(tracker_state *s, uint16_t now, uint8_t state)
{
    unsigned ch;
    /* Drop stale future events, mute the owned DOC at a near-future deadline,
     * then release owner only AFTER these writes have been executed. */
    tracker_write(REG_FLUSH, 0xA5);
    for (ch=0; ch<4; ++ch)
        tracker_halt((uint16_t)(now+4u), (uint8_t)ch);
    vTaskDelay(pdMS_TO_TICKS(25));
    tracker_write(REG_OWNER, 0);
    tracker_write(REG_STATE, state);
    s->active=0;
    s->finishing=0;
}

static void tracker_begin(tracker_state *s, uint16_t now)
{
    memset(s->base_fc,0,sizeof s->base_fc);
    memset(s->vol,0,sizeof s->vol);
    s->row=0;
    s->tick=0;
    s->time_next=(uint16_t)(now+100u);
    s->active=1;
    s->finishing=0;
    tracker_write(REG_FLUSH, 0xA5);
    tracker_write(REG_OWNER, 1);
    tracker_write(REG_STATE, STATE_PLAY);
    osd_log("SENSEI P1D: MCU/FPGA TRACKER START");
}

void sensei_tracker_task(void *unused)
{
    uint8_t st[13];
    tracker_state s;
    (void)unused;
    memset(&s,0,sizeof s);
    s.last_seq=0xFF;

    for (;;) {
        uint16_t now;
        uint8_t seq,cmd,arg,level;
        tracker_read(st);
        if (st[0]!=0x53 || st[1]!=0x1D || !(st[12]&1u)) {
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;  /* old FPGA, disabled personality or not configured */
        }
        seq=st[3]; cmd=st[2]; arg=st[4]; level=st[6];
        now=(uint16_t)((uint16_t)st[8] | ((uint16_t)st[9]<<8));
        if (seq!=s.last_seq) {
            s.last_seq=seq;
            if (cmd==2 && s.active) {
                tracker_stop(&s,now,STATE_IDLE);
            } else if (cmd==1 && !s.active) {
                if (arg==0) tracker_begin(&s,now);
                else tracker_write(REG_STATE,STATE_ERROR);
            }
        }
        if (s.active && !(st[12] & 0x02u)) {
            /* A2 reset, audio-mode change, or IIe C0CF panic revoked
             * FPGA ownership: immediately stop sending timed events. */
            s.active=0;
            s.finishing=0;
            tracker_write(REG_STATE, STATE_IDLE);
        }
        if (s.active) {
            /* Look ahead 80 ms, bounded by FIFO occupancy. This isolates
             * audio timing from USB/Disk/FreeRTOS scheduling jitter. */
            if (s.row<SONG_ROWS && level<=FIFO_SAFE_LEVEL &&
                (int16_t)((uint16_t)(now+80u)-s.time_next)>=0) {
                tracker_emit_tick(&s);
            }
            if (s.row==SONG_ROWS && !s.finishing) {
                s.finishing=1;
                s.time_finish=(uint16_t)(s.time_next+25u);
            }
            if (s.finishing && (int16_t)(now-s.time_finish)>=0) {
                tracker_stop(&s,now,STATE_DONE);
                osd_log("SENSEI P1D: DONE 192 ROWS");
            }
        }
        vTaskDelay(pdMS_TO_TICKS(5));
    }
}
