/*
 * SenseiPlay8 P2Y — native BL616 NinjaTrackerPlus score replayer.
 *
 * The score stays in its NTP byte format: note, NTP record, effect, argument.
 * Sample bytes were prepared by the original NTP converter and are uploaded
 * byte-exact; each instrument catalog entry is an original DOC page/RTS.
 *
 * Baseline effects mirror the 2018-2021 NinjaTrackerPlus 65816 player:
 * 0,1,2,3,4,5,6,A,B,C,D,F,E6,E9,EC,ED.
 * NTP-specific differences from P2U: sampled instrument without a new note
 * retriggers the previous note; stereo comes from the original DOC output
 * field; nonideal split sustain uses FPGA completion retarget, not P2U SWAP.
 *
 * This is intentionally NOT a blind port of the original 65816 code.
 * Remaining fidelity targets: exact original fine-pitch tables, streaming,
 * more effects, 5-octave finetune, and all >4-channel layouts.
 */
#include "sensei_ntp_native.h"
#include <string.h>

static const uint16_t note_period[72] = {
    1712,1616,1525,1440,1357,1281,1209,1141,1077,1017,961,907,
    856,808,762,720,678,640,604,570,538,508,480,453,
    428,404,381,360,339,320,302,285,269,254,240,226,
    214,202,190,180,170,160,151,143,135,127,120,113,
    107,101,95,90,85,80,76,71,67,64,60,57,
    53,50,47,45,42,40,37,35,33,31,30,28
};
static const uint16_t semi_q12[16] = {
    4096,4339,4597,4870,5160,5467,5793,6137,
    6502,6889,7299,7733,8192,8678,9195,9741
};
static const uint8_t sine[32] = {
    0,25,49,74,98,120,141,161,180,197,212,225,236,244,250,253,
    255,253,250,244,236,225,212,197,180,161,141,120,98,74,49,25
};
static uint16_t fc(uint16_t p)
{
    return p ? (uint16_t)((69013u+p/2u)/p) : 0;
}
static uint8_t limit64(int x)
{
    return (uint8_t)(x<0?0:x>64?64:x);
}
static uint8_t doc_volume(uint8_t v)
{
    /* NinjaTrackerPlus: lookup 0,4,8,...252,255,255 (NOT P2U's 3x). */
    return v>=64u?255u:(uint8_t)(v*4u);
}
static void send_pitch(sensei_doc_event_t out,uint16_t when,
                       uint8_t channel,uint16_t freq)
{
    uint8_t a=(uint8_t)(channel*2u);
    out(when,a,(uint8_t)freq);
    out(when,(uint8_t)(a+1u),(uint8_t)freq);
    out(when,(uint8_t)(0x20u+a),(uint8_t)(freq>>8));
    out(when,(uint8_t)(0x21u+a),(uint8_t)(freq>>8));
}
static void send_volume(sensei_doc_event_t out,uint16_t when,
                        uint8_t channel,uint8_t volume)
{
    uint8_t a=(uint8_t)(channel*2u);
    uint8_t v=doc_volume(volume);
    out(when,(uint8_t)(0x40u+a),v);
    out(when,(uint8_t)(0x41u+a),v);
}
static void start_note(sensei_ntp_player_t *s,sensei_doc_event_t out,
                       uint16_t when,uint8_t ch,uint16_t period,
                       uint8_t inst,uint8_t volume)
{
    uint8_t a,b,pan,actl,bctl;
    const uint8_t *d;
    if(!inst || inst>=32u || !period)return;
    ++s->note_starts[ch];
    a=(uint8_t)(ch*2u);b=(uint8_t)(a+1u);
    d=&s->catalog[(unsigned)inst*8u];pan=s->pan[ch];
    actl=d[2];bctl=d[6];
    if(s->irq_instruments[inst]) {
        /* Original NTP 65816: A=IRQ|SWAP, B=SWAP. On A's first
         * waveform-end the FPGA retargets A to B's loop and clears IRQ.
         * Thus both sides subsequently play loop data, not the attack. */
        actl=0x0Eu;
        bctl=0x06u;
    }
    out(when,(uint8_t)(0xA0u+a),(uint8_t)(pan|1u));
    out(when,(uint8_t)(0xA0u+b),(uint8_t)(pan|1u));
    out(when,(uint8_t)(0x80u+a),d[0]);
    out(when,(uint8_t)(0xC0u+a),d[1]);
    if(d[7]&1u) {
        out(when,(uint8_t)(0x80u+b),d[4]);
        out(when,(uint8_t)(0xC0u+b),d[5]);
    }
    send_pitch(out,when,ch,fc(period));
    send_volume(out,when,ch,volume);
    out(when,(uint8_t)(0xA0u+b),(uint8_t)(pan|bctl|1u));
    out(when,(uint8_t)(0xA0u+a),(uint8_t)(pan|actl));
}
static void pitch_if(sensei_ntp_player_t *s,sensei_doc_event_t emit,
                     uint16_t when,uint8_t channel,uint16_t freq)
{
    if(s->audition_mask&(1u<<channel))
        send_pitch(emit,when,channel,freq);
}
static void volume_if(sensei_ntp_player_t *s,sensei_doc_event_t emit,
                      uint16_t when,uint8_t channel,uint8_t v)
{
    if(s->audition_mask&(1u<<channel))
        send_volume(emit,when,channel,v);
}
static void start_if(sensei_ntp_player_t *s,sensei_doc_event_t emit,
                     uint16_t when,uint8_t channel,uint16_t period,
                     uint8_t inst,uint8_t vol)
{
    if(s->audition_mask&(1u<<channel))
        start_note(s,emit,when,channel,period,inst,vol);
    else
        ++s->note_starts[channel]; /* interpreter still tracks muted notes */
}
static void slide_to(sensei_ntp_channel_t *c)
{
    if(!c->target || !c->slide || !c->period)return;
    if(c->period<c->target) {
        unsigned p=(unsigned)c->period+c->slide;
        c->period=(uint16_t)(p>c->target?c->target:p);
    } else if(c->period>c->target) {
        c->period=(uint16_t)((c->period-c->target)<=c->slide?
                             c->target:c->period-c->slide);
    }
}
static void tick_zero(sensei_ntp_player_t *s,sensei_doc_event_t emit,
                      uint16_t at)
{
    uint32_t row_off;
    const uint8_t *ev;
    s->jump_pending=s->break_pending=s->loop_pending=0;
    row_off=(uint32_t)s->orders[s->order_pos]*1024u+(uint32_t)s->row*16u;
    for(uint8_t ch=0;ch<4u;ch++) {
        sensei_ntp_channel_t *c=&s->ch[ch];
        uint8_t note,inst_raw,fx,arg,sub;
        bool delay,previous_mod;
        ev=s->raw_patterns+row_off+(uint32_t)ch*4u;
        note=ev[0];inst_raw=ev[1];fx=ev[2];arg=ev[3];sub=arg>>4;
        previous_mod=c->previous_pitch_fx!=0u;
        c->effect=fx;c->arg=arg;
        c->delay_tick=0u;
        c->previous_pitch_fx=(uint8_t)((fx==0u&&arg!=0u)||fx==4u||fx==6u);
        if(inst_raw) {
            uint8_t mapped=s->inst_map[inst_raw];
            c->raw_instrument=inst_raw;
            c->instrument=mapped;
            c->volume=s->catalog[(unsigned)mapped*8u+3u];
            if(!note)note=c->note; /* NinjaTrackerPlus re-triggers old note */
        }
        delay=(fx==14u && sub==13u && (arg&15u)!=0u);
        if(fx==3u || fx==5u) {
            if(note) {
                c->target=note_period[note-1u];
                if(!c->period)c->period=c->target;
            }
            if(fx==3u && arg)c->slide=arg;
            if(fx==5u && arg)c->volslide=arg;
        } else if(note && !delay) {
            c->note=note;
            c->period=note_period[note-1u];
            c->vib_phase=0u;
            start_if(s,emit,at,ch,c->period,c->instrument,c->volume);
        } else if(note) {
            c->delay_tick=(uint8_t)(arg&15u);
            c->delay_note=note;
            c->delay_inst=c->instrument;
            c->delay_period=note_period[note-1u];
        }
        if(previous_mod && c->period && (!note || fx==3u || fx==5u))
            pitch_if(s,emit,at,ch,fc(c->period));
        if(fx==1u || fx==2u) {if(arg)c->slide=arg;}
        if(fx==4u) {
            if(arg>>4)c->vib_speed=arg>>4;
            if(arg&15u)c->vib_depth=arg&15u;
            c->vib_phase=0u;
        }
        if((fx==10u||fx==5u||fx==6u)&&arg)c->volslide=arg;
        if(fx==12u) {
            c->volume=limit64(arg);
            volume_if(s,emit,at,ch,c->volume);
        }
        if(fx==15u) {
            if(!arg)s->done=1u; /* NTP F00 means stop music */
            else if(arg<32u)s->speed=arg;
            else s->bpm=arg; /* 50 Hz timer equivalent */
        }
        if(fx==11u){s->jump_pending=1u;s->jump_to=arg&0x7fu;}
        if(fx==13u) {
            unsigned row=(unsigned)(arg>>4)*10u+(arg&15u);
            s->break_pending=1u;
            s->break_row=(uint8_t)(row<64u?row:0u);
        }
        if(fx==14u && sub==6u) {
            uint8_t count=arg&15u;
            if(!count) s->loop_start=(uint8_t)s->row;
            else if(!s->loop_active) {
                s->loop_active=1u;s->loop_count=count;
                s->loop_pending=1u;s->loop_to=s->loop_start;
            } else if(--s->loop_count) {
                s->loop_pending=1u;s->loop_to=s->loop_start;
            } else s->loop_active=0u;
        }
        if(fx==14u && sub==12u && (arg&15u)==0u) {
            c->volume=0u;
            volume_if(s,emit,at,ch,0u);
        }
    }
}
static void tick_effects(sensei_ntp_player_t *s,sensei_doc_event_t emit,
                         uint16_t at)
{
    for(uint8_t ch=0;ch<4u;ch++) {
        sensei_ntp_channel_t *c=&s->ch[ch];
        uint8_t fx=c->effect,arg=c->arg;
        bool pitch_changed=false,volume_changed=false;
        uint16_t value=0;
        if(fx==0u && arg && c->period) {
            uint8_t shift=(s->tick%3u==1u)?arg>>4:
                          (s->tick%3u==2u)?arg&15u:0u;
            value=(uint16_t)(((uint32_t)fc(c->period)*
                              semi_q12[shift]+2048u)>>12);
            pitch_changed=true;
        } else if(fx==1u && c->period) {
            c->period=(uint16_t)(c->period>c->slide?
                                 c->period-c->slide:1u);
            value=fc(c->period);pitch_changed=true;
        } else if(fx==2u && c->period) {
            unsigned period=(unsigned)c->period+c->slide;
            c->period=(uint16_t)(period>4095u?4095u:period);
            value=fc(c->period);pitch_changed=true;
        } else if((fx==3u||fx==5u)&&c->period) {
            slide_to(c);value=fc(c->period);pitch_changed=true;
        } else if((fx==4u||fx==6u)&&c->period) {
            uint8_t phase=c->vib_phase&63u;
            int wave=sine[phase&31u];
            int target;
            if(phase&32u)wave=-wave;
            target=(int)c->period+((wave*(int)c->vib_depth)>>7);
            if(target<1)target=1;if(target>4095)target=4095;
            value=fc((uint16_t)target);pitch_changed=true;
            c->vib_phase=(uint8_t)((c->vib_phase+4u*c->vib_speed)&63u);
        }
        if(fx==10u||fx==5u||fx==6u) {
            uint8_t up=c->volslide>>4,down=c->volslide&15u;
            c->volume=limit64((int)c->volume+(up?(int)up:-(int)down));
            volume_changed=true;
        }
        if(fx==14u) {
            uint8_t sub=arg>>4,n=arg&15u;
            if(sub==9u && n && s->tick%n==0u &&
               c->instrument && c->period)
                start_if(s,emit,at,ch,c->period,c->instrument,c->volume);
            else if(sub==12u && n==s->tick) {
                c->volume=0u;volume_changed=true;
            } else if(sub==13u && c->delay_tick==s->tick && c->delay_note) {
                c->note=c->delay_note;c->period=c->delay_period;
                start_if(s,emit,at,ch,c->period,c->delay_inst,c->volume);
                c->delay_note=0u;c->delay_tick=0u;
            }
        }
        if(pitch_changed)pitch_if(s,emit,at,ch,value);
        if(volume_changed)volume_if(s,emit,at,ch,c->volume);
    }
}
bool sensei_ntp_init(sensei_ntp_player_t *s,
                      const uint8_t *raw_patterns,uint8_t pattern_count,
                      const uint8_t *orders,uint8_t order_count,
                      const uint8_t *catalog,const uint8_t *pan,
                      const uint8_t inst_map[64],
                      const uint8_t irq_instruments[32],uint16_t now)
{
    if(!s||!raw_patterns||!pattern_count||!orders||!order_count||
       !catalog||!pan||!inst_map||!irq_instruments||
       order_count>128u)return false;
    for(unsigned i=0;i<order_count;i++)if(orders[i]>=pattern_count)return false;
    memset(s,0,sizeof(*s));
    s->raw_patterns=raw_patterns;s->pattern_count=pattern_count;
    s->orders=orders;s->order_count=order_count;s->catalog=catalog;
    memcpy(s->pan,pan,4u);
    memcpy(s->inst_map,inst_map,64u);
    memcpy(s->irq_instruments,irq_instruments,32u);
    s->speed=6u;s->bpm=125u;s->audition_mask=0x0fu;
    s->next_tick_fp=((uint32_t)(uint16_t)(now+100u))<<16;
    return true;
}
bool sensei_ntp_tick(sensei_ntp_player_t *s,sensei_doc_event_t emit)
{
    uint16_t at;
    if(!s||s->done||!emit)return false;
    at=sensei_ntp_next_ms(s);
    if(s->tick==0u)tick_zero(s,emit,at);
    else tick_effects(s,emit,at);
    if(s->done)return true;
    s->next_tick_fp+=(uint32_t)(((uint64_t)2500u<<16)/s->bpm);
    if(++s->tick>=s->speed) {
        uint8_t old_pos=s->order_pos;
        s->tick=0u;
        if(++s->visited_rows>65535u)s->done=1u;
        else if(s->jump_pending||s->break_pending) {
            s->order_pos=s->jump_pending?s->jump_to:
                         (uint8_t)(s->order_pos+1u);
            s->row=s->break_pending?s->break_row:0u;
        } else if(s->loop_pending) s->row=s->loop_to;
        else if(++s->row>=64u) {
            s->row=0u;++s->order_pos;
        }
        if(s->order_pos!=old_pos) {
            s->loop_start=s->loop_count=s->loop_active=0u;
        }
        if(s->order_pos>=s->order_count)s->done=1u;
    }
    return true;
}
uint16_t sensei_ntp_next_ms(const sensei_ntp_player_t *s)
{
    return (uint16_t)(s->next_tick_fp>>16);
}
bool sensei_ntp_done(const sensei_ntp_player_t *s)
{
    return s!=NULL && s->done!=0u;
}
