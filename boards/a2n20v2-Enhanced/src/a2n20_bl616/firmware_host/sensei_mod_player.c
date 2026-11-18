/* SenseiPlay8 P1E: BL616 real-time ProTracker tick engine.
 * P1D FPGA remains responsible for deterministic DOC register timing.
 * Copyright (c) 2026 Petar Puskarich and contributors.
 *
 * Supports full played-row streams with: 0xy/1xx/2xx/3xx/4xy/5xy/6xy,
 * Axy/Cxx/Fxx, E9x retrigger, ECx note cut, EDx note delay.
 * Bxx/Dxx/E6x song flow is flattened offline, without flattening effects.
 * No float, no CPU-side tick processing, no change to Native DOC ABI.
 */
#include "sensei_mod_player.h"
#include <string.h>

#if defined(__has_include)
#if __has_include("sensei_p1e_local_data.h")
#include "sensei_p1e_local_data.h" /* private, ignored by Git */
#endif
#endif

static const uint16_t pitch_multiplier[16] = {
    4096,4339,4597,4870,5160,5467,5793,6137,
    6502,6889,7299,7733,8192,8678,9195,9741
};
static const int8_t sinus[32] = {
    0,25,49,74,98,120,141,161,180,197,212,225,236,244,250,253,
    255,253,250,244,236,225,212,197,180,161,141,120,98,74,49,25
};

bool sensei_mod_available(void)
{
#ifdef SENSEI_HAS_LOCAL_MODS
    return true;
#else
    return false;
#endif
}

uint16_t sensei_mod_next_ms(const sensei_mod_player_t *s)
{
    return (uint16_t)(s->next_tick_fp >> 16);
}

bool sensei_mod_done(const sensei_mod_player_t *s) { return !!s->done; }

bool sensei_mod_init(sensei_mod_player_t *s, uint8_t song_id, uint16_t now)
{
    memset(s, 0, sizeof(*s));
#ifdef SENSEI_HAS_LOCAL_MODS
    if (song_id < 1 || song_id > 2) return false;
    s->song = &sensei_local_songs[song_id-1];
    if (!s->song->rows || !s->song->catalog || !s->song->count) return false;
    s->speed=6; s->bpm=125;
    s->next_tick_fp = ((uint32_t)(uint16_t)(now + 100u)) << 16;
    return true;
#else
    (void)song_id; (void)now;
    return false;
#endif
}

static uint16_t fc_from_period(uint16_t period)
{
    if (!period) return 0;
    return (uint16_t)((69013u + period / 2u) / period);
}
static uint16_t arp_fc(uint16_t period,uint8_t semitone)
{
    return (uint16_t)(((uint32_t)fc_from_period(period) *
                       pitch_multiplier[semitone & 15u] + 2048u) >> 12);
}

static void pitch_write(sensei_doc_event_t out,uint16_t ms,uint8_t ch,uint16_t fc)
{
    out(ms,ch,(uint8_t)fc);
    out(ms,(uint8_t)(0x20u+ch),(uint8_t)(fc>>8));
}
static void volume_write(sensei_doc_event_t out,uint16_t ms,uint8_t ch,uint8_t volume)
{
    out(ms,(uint8_t)(0x40u+ch),(uint8_t)(volume*3u));
}
static void note_start(const sensei_mod_player_t *s,sensei_doc_event_t out,
                       uint16_t ms,uint8_t ch,uint16_t period,uint8_t inst,uint8_t volume)
{
    uint8_t ctrl, wtp, rts;
    const uint8_t *d;
    if (!inst || inst >= 32 || !period) return;
    d=s->song->catalog+(unsigned)inst*4u;
    wtp=d[0];rts=d[1];
    ctrl=(uint8_t)(((ch==1 || ch==2) ? 0x10u : 0u) | d[2]);
    out(ms,(uint8_t)(0xA0u+ch),(uint8_t)(ctrl|1u));
    out(ms,(uint8_t)(0x80u+ch),wtp);
    out(ms,(uint8_t)(0xC0u+ch),rts);
    pitch_write(out,ms,ch,fc_from_period(period));
    volume_write(out,ms,ch,volume);
    out(ms,(uint8_t)(0xA0u+ch),(uint8_t)(ctrl&0xFEu));
}
static uint8_t clamp64(int volume)
{
    return (uint8_t)(volume<0 ? 0 : (volume>64 ? 64 : volume));
}

static void slide_volume(sensei_mod_chan_t *c)
{
    uint8_t arg=c->volslide,up=arg>>4,down=arg&15;
    if (up) c->volume=clamp64(c->volume+up);
    else c->volume=clamp64((int)c->volume-down);
}
static void slide_towards_target(sensei_mod_chan_t *c)
{
    if (!c->target || !c->porta_speed) return;
    if (c->period < c->target) {
        unsigned step=(unsigned)c->period+c->porta_speed;
        c->period=(uint16_t)(step>=c->target?c->target:step);
    } else if (c->period > c->target) {
        c->period=(uint16_t)(c->period-c->target<=c->porta_speed?
                             c->target:c->period-c->porta_speed);
    }
}
static uint16_t vibrato_fc(sensei_mod_chan_t *c)
{
    uint8_t phase=c->vib_phase & 63;
    int32_t wave=sinus[phase & 31];
    if (phase & 32u) wave=-wave;
    /* ProTracker vibrato depth is measured in small period steps. */
    int32_t altered=(int32_t)c->period +
        ((wave * (int32_t)c->vib_depth + 128) >> 8);
    if (altered < 1) altered=1;
    if (altered > 4095) altered=4095;
    c->vib_phase=(uint8_t)((c->vib_phase+c->vib_speed)&63);
    return fc_from_period((uint16_t)altered);
}
static void process_tick0(sensei_mod_player_t *s,sensei_doc_event_t out,
                          uint16_t ms)
{
    const uint8_t *row=s->song->rows+(uint32_t)s->row*16u;
    unsigned ch;
    for(ch=0;ch<4;ch++) {
        const uint8_t *ev=row+ch*4u;
        uint8_t inst=(uint8_t)((ev[0]&0xF0u)|(ev[2]>>4));
        uint16_t period=(uint16_t)(((ev[0]&0x0Fu)<<8)|ev[1]);
        uint8_t fx=ev[2]&15, arg=ev[3];
        sensei_mod_chan_t *c=&s->ch[ch];
        bool delay=(fx==14 && (arg>>4)==13 && (arg&15)!=0);
        uint8_t sub=arg>>4;
        c->fx=fx;c->param=arg;
        c->delayed_tick=0;
        if (inst) {
            c->instrument=inst;
            c->volume=s->song->catalog[(unsigned)inst*4u+3u];
        }
        if (fx==3 || fx==5) {
            if(period) {
                c->target=period;
                if(!c->period) c->period=period;
            }
            if (fx==3 && arg) c->porta_speed=arg;
            if (fx==5 && arg) c->volslide=arg;
        } else if(period && !delay) {
            c->period=period;
            c->vib_phase=0;
            note_start(s,out,ms,(uint8_t)ch,period,c->instrument,c->volume);
        } else if(period && delay) {
            c->delayed_tick=arg&15u;
            c->delayed_period=period;
            c->delayed_inst=c->instrument;
        }
        if (fx==15 && arg) {
            if (arg<32) s->speed=arg;
            else s->bpm=arg;
        }
        if (fx==12) {
            c->volume=clamp64(arg);
            volume_write(out,ms,(uint8_t)ch,c->volume);
        }
        if (fx==4) {
            if(arg>>4) c->vib_speed=arg>>4;
            if(arg&15) c->vib_depth=arg&15;
        }
        if ((fx==10 || fx==6) && arg) c->volslide=arg;
        if (fx==1 || fx==2) {
            if(arg) c->porta_speed=arg;
        }
        if (fx==14 && sub==12 && (arg&15)==0) {
            c->volume=0;
            volume_write(out,ms,(uint8_t)ch,0);
        }
    }
}

static void process_tick_nonzero(sensei_mod_player_t *s,sensei_doc_event_t out,
                                 uint16_t ms)
{
    unsigned ch;
    for(ch=0;ch<4;ch++) {
        sensei_mod_chan_t *c=&s->ch[ch];
        uint8_t fx=c->fx,arg=c->param;
        uint16_t fc=0;
        bool update_pitch=false,update_volume=false;
        if (fx==0 && arg && c->period) {
            uint8_t shift=(uint8_t)((s->tick%3u)==1u ? arg>>4 :
                                      ((s->tick%3u)==2u ? arg&15u : 0u));
            fc=arp_fc(c->period,shift);
            update_pitch=true;
        } else if (fx==1 && c->period) {
            c->period=(uint16_t)(c->period>c->porta_speed?
                                  c->period-c->porta_speed:1u);
            fc=fc_from_period(c->period);
            update_pitch=true;
        } else if (fx==2 && c->period) {
            c->period=(uint16_t)(c->period+c->porta_speed);
            fc=fc_from_period(c->period);
            update_pitch=true;
        } else if ((fx==3 || fx==5) && c->period) {
            slide_towards_target(c);
            fc=fc_from_period(c->period);
            update_pitch=true;
        } else if ((fx==4 || fx==6) && c->period) {
            fc=vibrato_fc(c);
            update_pitch=true;
        }
        if (fx==10 || fx==5 || fx==6) {
            slide_volume(c);
            update_volume=true;
        }
        if (fx==14) {
            if ((arg>>4)==9 && (arg&15) && s->tick%(arg&15u)==0
                && c->instrument && c->period) {
                note_start(s,out,ms,(uint8_t)ch,c->period,c->instrument,c->volume);
            } else if ((arg>>4)==12 && (arg&15)==s->tick) {
                c->volume=0; update_volume=true;
            } else if ((arg>>4)==13 && c->delayed_tick==s->tick) {
                c->period=c->delayed_period;
                note_start(s,out,ms,(uint8_t)ch,c->period,c->delayed_inst,c->volume);
                c->delayed_tick=0;
            }
        }
        if (update_pitch) pitch_write(out,ms,(uint8_t)ch,fc);
        if (update_volume) volume_write(out,ms,(uint8_t)ch,c->volume);
    }
}

bool sensei_mod_tick(sensei_mod_player_t *s, sensei_doc_event_t emit)
{
    uint16_t when;
    if (!s->song || s->done || !emit) return false;
    when=sensei_mod_next_ms(s);
    if(s->tick==0) process_tick0(s,emit,when);
    else process_tick_nonzero(s,emit,when);
    /* One tick = 2.5/BPM seconds, rounded only at FPGA 1-ms dispatch.
     * 64-bit division is once per tick (~20-50ms), on the BL616. */
    s->next_tick_fp += (uint32_t)(((uint64_t)2500u<<16)/s->bpm);
    if (++s->tick>=s->speed) {
        s->tick=0;
        if (++s->row>=s->song->count) s->done=1;
    }
    return true;
}
