#ifndef SENSEI_MOD_PLAYER_H
#define SENSEI_MOD_PLAYER_H

/* Four-channel ProTracker tick interpreter for the Sensei P1D FPGA FIFO.
 * Song pattern assets are generated locally from user-provided MODs; no
 * copyrighted patterns or samples are committed to this repository. */
#include <stdint.h>
#include <stdbool.h>

typedef void (*sensei_doc_event_t)(uint16_t when, uint8_t doc_reg, uint8_t data);
typedef struct {
    const uint8_t *rows;     /* flattened played 16-byte rows */
    uint16_t count;
    const uint8_t *catalog;  /* 32 instruments x [WTP,RTS,CTRL,VOL] */
} sensei_mod_song_t;

typedef struct {
    uint16_t period, target, delayed_period;
    uint8_t instrument, volume, fx, param;
    uint8_t porta_speed, vib_speed, vib_depth, vib_phase;
    uint8_t volslide, delayed_inst, delayed_tick;
    uint8_t last_ctrl;
} sensei_mod_chan_t;

typedef struct {
    const sensei_mod_song_t *song;
    sensei_mod_chan_t ch[4];
    uint16_t row;
    uint8_t tick, speed, bpm, done;
    uint32_t next_tick_fp;  /* FPGA milliseconds Q16.16 */
} sensei_mod_player_t;

/* Song IDs: 1 = 15k Boogie, 2 = 1 Minute Dead Waltz. ID0 retains P1D demo. */
bool sensei_mod_init(sensei_mod_player_t *state, uint8_t song_id, uint16_t now);
bool sensei_mod_tick(sensei_mod_player_t *state, sensei_doc_event_t emit);
uint16_t sensei_mod_next_ms(const sensei_mod_player_t *state);
bool sensei_mod_done(const sensei_mod_player_t *state);
bool sensei_mod_available(void);

#endif
