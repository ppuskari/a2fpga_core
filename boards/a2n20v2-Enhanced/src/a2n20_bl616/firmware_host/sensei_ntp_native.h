#ifndef SENSEI_NTP_NATIVE_H
#define SENSEI_NTP_NATIVE_H
/*
 * Native four-track NinjaTrackerPlus score interpreter, running on BL616.
 * Independent of the MOD/ProTracker interpreter; no format re-encoding.
 * DOC note/oscillator writes remain timestamped through the P2 FIFO.
 *
 * Nonideal split loops use CTRL 0x0E to request the optional FPGA-side
 * first-end retarget assist. Only enable this engine with the P2Y FPGA.
 */
#include <stdbool.h>
#include <stdint.h>
#include "sensei_mod_player.h" /* sensei_doc_event_t callback ABI */

typedef struct {
    uint8_t note, instrument, raw_instrument, volume, effect, arg;
    uint8_t slide, vib_speed, vib_depth, vib_phase, volslide;
    uint8_t delay_tick, delay_note, delay_inst;
    uint16_t period, target, delay_period;
    uint8_t previous_pitch_fx;
} sensei_ntp_channel_t;

typedef struct {
    const uint8_t *raw_patterns; /* 4 NTP bytes/track/row */
    const uint8_t *orders;
    const uint8_t *catalog;      /* already DOC-ready 32*8 table */
    uint8_t pan[4];              /* 0x10=left, 0=right */
    uint8_t inst_map[64];        /* NTP record -> logical catalog instrument */
    uint8_t irq_instruments[32]; /* first-end split-loop retarget required */
    uint8_t pattern_count, order_count, order_pos, speed, bpm, tick;
    uint8_t done, audition_mask, jump_pending, break_pending;
    uint8_t jump_to, break_row, loop_start, loop_count, loop_active;
    uint8_t loop_pending, loop_to;
    uint16_t row;
    uint32_t visited_rows, next_tick_fp, note_starts[4];
    sensei_ntp_channel_t ch[4];
} sensei_ntp_player_t;

bool sensei_ntp_init(sensei_ntp_player_t *s,
                      const uint8_t *raw_patterns, uint8_t pattern_count,
                      const uint8_t *orders, uint8_t order_count,
                      const uint8_t *catalog, const uint8_t *pan,
                      const uint8_t inst_map[64],
                      const uint8_t irq_instruments[32], uint16_t now);
bool sensei_ntp_tick(sensei_ntp_player_t *s, sensei_doc_event_t emit);
uint16_t sensei_ntp_next_ms(const sensei_ntp_player_t *s);
bool sensei_ntp_done(const sensei_ntp_player_t *s);
#endif
