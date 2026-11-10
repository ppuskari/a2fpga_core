/*
 * P10 SSI263 hybrid audio renderer for BL616 firmware_host.
 *
 * New FPGA XFER space 5: 8B host write event
 *  [addr,data,seq16LE,xck32LE], auto-pop after last byte.
 * XFER space 4 read @0x800000: 24B transport status.
 * XFER space 4 write @0: mono PCM16LE, 44.1/22.05/11.025 kHz.
 * XFER space 4 write @0x800000: PCM ring reset.
 * XFER space 4 write @0x800001: rate code 0/1/2 (new FPGA only).
 * FPGA holds each low-rate source sample for 1/2/4 HDMI audio ticks.
 *
 * Audio latency is ~12-46 ms depending on occupancy; SSI A/R remains
 * entirely FPGA-owned. Model renders future PCM on each service turn.
 * This first experiment intentionally does NOT claim timestamp-exact
 * speech alignment or real-time MCU scheduling qualification.
 */
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdio.h>
#include "FreeRTOS.h"
#include "task.h"
#include "bflb_mtimer.h"
#include "fpga_spi.h"
#include "osd_console.h"
#include "ssi263.h"
#include "ssi263_hybrid.h"
#include "ssi263_audio_edges.h"

#define SSI_PCM_SPACE      4u
#define SSI_EVENTS_SPACE   5u
#define SSI_STATUS_ADDR    0x800000u
#define SSI_RATE_ADDR      0x800001u
#ifndef SSI263_PCM_RATE_DIV
#define SSI263_PCM_RATE_DIV 2u /* 1=44.1k; 2=22.05k default; 4=11.025k */
#endif
#if SSI263_PCM_RATE_DIV != 1 && SSI263_PCM_RATE_DIV != 2 && SSI263_PCM_RATE_DIV != 4
#error "SSI263_PCM_RATE_DIV must be 1, 2, or 4"
#endif
#define BLOCK_SAMPLES      128u
#define BLOCK_BYTES        (2u*BLOCK_SAMPLES)
#define EVENTS_PER_BURST   12u
#define STATUS_LEN         26u /* legacy 24 bytes plus R6 capability/rate */
#define TARGET_BUFFER      1024u
#define XCK_HZ             1020000.0f
/* Optional, controlled R7 A/B knobs. The Pico model and phoneme ROM
 * remain intact. Do not globally low-pass or suppress all noise. */
#ifndef SSI263_R7_ATTACK_US
#define SSI263_R7_ATTACK_US 0u /* R9B true bypass: no edge shaper at all */
#endif
#ifndef SSI263_R7_PREQUIET_MS
#define SSI263_R7_PREQUIET_MS 18u
#endif
#ifndef SSI263_R7_PREQUIET_ABS
#define SSI263_R7_PREQUIET_ABS 16u
#endif
#ifndef SSI263_R7_IDLE_ZERO_MS
#define SSI263_R7_IDLE_ZERO_MS 2500u
#endif
#ifndef SSI263_R7_NOISE_PERCENT
#define SSI263_R7_NOISE_PERCENT 100u /* 100=unaltered; 85/70 A/B only */
#endif
#if SSI263_R7_NOISE_PERCENT > 100u
#error "R7 noise-percent knob must be 0..100"
#endif

/* Diagnostic A/B option; default preserves the original Pico carrier.
 * 1 substitutes -200dB carrier_rel_db to make carrier negligible at PCM16,
 * without altering the pinned Pico model source or other phoneme sources.
 * Deliberately separate this experiment from the 0us attack baseline. */
#ifndef SSI263_R9B_CARRIER_QUIET_TEST
#define SSI263_R9B_CARRIER_QUIET_TEST 0u
#endif
#if SSI263_R9B_CARRIER_QUIET_TEST != 0u && SSI263_R9B_CARRIER_QUIET_TEST != 1u
#error "SSI263_R9B_CARRIER_QUIET_TEST must be 0 or 1"
#endif

static uint8_t status_buf[STATUS_LEN];
static uint8_t events_buf[EVENTS_PER_BURST*8u];
static uint8_t pcm_buf[BLOCK_BYTES];
static real float_samples[BLOCK_SAMPLES+1u];
static short signed_samples[BLOCK_SAMPLES+1u];

static uint32_t read16(const uint8_t *b)
{
    return (uint32_t)b[0] | ((uint32_t)b[1]<<8);
}
static uint32_t read32(const uint8_t *b)
{
    return (uint32_t)b[0] | ((uint32_t)b[1]<<8) |
       ((uint32_t)b[2]<<16) | ((uint32_t)b[3]<<24);
}
static bool read_status(void)
{
    fpga_spi_xfer_read(SSI_PCM_SPACE,SSI_STATUS_ADDR,
                       status_buf,STATUS_LEN);
    return status_buf[0]=='S' && status_buf[1]=='P' &&
           status_buf[2]==1 && status_buf[22]=='P' &&
           status_buf[23]=='1';
}
static void ring_reset(void)
{
    uint8_t one=1;
    fpga_spi_xfer_write(SSI_PCM_SPACE,SSI_STATUS_ADDR,&one,1);
}

/* Old P10 FPGA returns 0x31 for the optional capability byte and must
 * continue receiving 44.1 kHz PCM. New FPGA: require write/readback ACK
 * before creating the software synthesizer at the lower rate. */
static unsigned configure_pcm_rate(void)
{
    if(status_buf[24]!=0xA6u)return 1u;
    const uint8_t wanted=(SSI263_PCM_RATE_DIV==4u)?2u:
                         (SSI263_PCM_RATE_DIV==2u)?1u:0u;
    for(unsigned attempt=0;attempt<3u;attempt++) {
        fpga_spi_xfer_write(SSI_PCM_SPACE,SSI_RATE_ADDR,&wanted,1u);
        if(read_status() && status_buf[24]==0xA6u &&
           status_buf[25]==wanted)return SSI263_PCM_RATE_DIV;
        vTaskDelay(pdMS_TO_TICKS(1));
    }
    /* A mismatched source and HDMI divider would corrupt timing. Explicitly
     * restore 44.1k and insist on an ACK; otherwise refuse speech startup. */
    const uint8_t fallback=0;
    fpga_spi_xfer_write(SSI_PCM_SPACE,SSI_RATE_ADDR,&fallback,1u);
    if(read_status() && status_buf[24]==0xA6u && status_buf[25]==0u)
        return 1u;
    return 0u;
}

/* Log a mismatch without pretending the SSI model is synchronized.
 * If a FIFO overflow occurs the CPU event stream is no longer complete;
 * power-cycle/restart is required for speech accuracy. */
void ssi263_hybrid_task(void *arg)
{
    (void)arg;
    ssi263_params params;
    ssi263_default_params(&params);
    params.xck_hz=XCK_HZ;
    params.noise_gain *= (real)SSI263_R7_NOISE_PERCENT/100.0f;
#if SSI263_R9B_CARRIER_QUIET_TEST
    params.carrier_rel_db=-200.0f; /* PCM16 effectively zero after quantization */
#endif
    while(!read_status())vTaskDelay(pdMS_TO_TICKS(100));
    const unsigned pcm_rate_div=configure_pcm_rate();
    if(!pcm_rate_div) {
        osd_log("P10 SSI263: RATE MODE ACK FAILED");
        vTaskDelete(NULL);
        return;
    }
    const unsigned pcm_hz=44100u/pcm_rate_div;
    const uint32_t block_budget_us=(uint32_t)
          ((uint64_t)BLOCK_SAMPLES*1000000u*pcm_rate_div/44100u);
    ssi263 *chip=ssi263_new(&params,ssi263_default_rom(),(real)pcm_hz);
    if(!chip) {
        osd_log("P10 SSI263: MODEL INIT FAILED");
        vTaskDelete(NULL);
        return;
    }
    uint16_t expect_seq=0;
    bool seq_valid=false,active=false,fault=false;
    uint32_t total_blocks=0,slow_blocks=0,late_events=0,last_report_ms=0;
    uint32_t rendered_samples=0;
    uint32_t last_stamp=0;
    uint32_t prev_blocks=0,peak_model_us=0,peak_spi_us=0;
    uint32_t over_budget_blocks=0,prev_over_budget=0;
    /* R9A: bounded, inexpensive PCM evidence. These are not silence gates.
     * qpk counts low-amplitude blocks, never suppresses their audio. */
    uint32_t r9_ar_blocks=0,r9_low_blocks=0;
    uint32_t r9_raw_peak=0,r9_post_peak=0,r9_low_peak=0;
    uint32_t report_interval_ms=10000u;
#if SSI263_R7_ATTACK_US > 0u
    ssi263_audio_edges edges;
    ssi263_audio_edges_init(&edges,pcm_hz,SSI263_R7_PREQUIET_MS,
                            SSI263_R7_ATTACK_US,SSI263_R7_PREQUIET_ABS);
#endif
    const uint32_t idle_zero_samples=(uint32_t)
        ((uint64_t)pcm_hz*SSI263_R7_IDLE_ZERO_MS/1000u);
    uint32_t silent_samples=0u,idle_blocks=0u;
    bool idle_fastpath=false;

    ring_reset();
    osd_log("P10 SSI263: Pico C hybrid online");
    osd_log("P10 SOURCE=%uHZ DIV=%u",pcm_hz,pcm_rate_div);
    osd_log("P10 R9B: ATTACK BYPASSED");
    osd_log("P10 R9B CARRIER=%s", SSI263_R9B_CARRIER_QUIET_TEST ? "QUIET" : "ORIGINAL");
    osd_log("P10 R8: FAST VOICED COS LUT512");
    for(;;) {
        if(!read_status()) {
            active=false;seq_valid=false;fault=true;
            silent_samples=0u;idle_fastpath=false;
            vTaskDelay(pdMS_TO_TICKS(20));
            continue;
        }
        const unsigned event_count=(unsigned)read16(status_buf+8);
        if(read16(status_buf+14)!=0)fault=true;
        unsigned burst=event_count>EVENTS_PER_BURST ?
               EVENTS_PER_BURST : event_count;

        if(burst) {
            /* Any SSI write wakes the model before the new command lands.
             * No time-based gating of sustained or noise-only phonemes. */
            silent_samples=0u;
            idle_fastpath=false;
            fpga_spi_xfer_read(SSI_EVENTS_SPACE,0,events_buf,
                                (uint16_t)(burst*8u));
            for(unsigned i=0;i<burst;i++) {
                const uint8_t *e=events_buf+i*8u;
                uint8_t reg=e[0],value=e[1];
                uint16_t seq=(uint16_t)read16(e+2);
                uint32_t stamp=read32(e+4);
                if(seq_valid && seq!=expect_seq) {
                    fault=true;
                    ++late_events;
                }
                expect_seq=(uint16_t)(seq+1u);
                seq_valid=true;
                last_stamp=stamp;
                if(reg>7u){fault=true;continue;}
                ssi263_write(chip,reg,value);
                if(reg==3u) {
                    active=(value&0x80u)==0u;
                    if(!active) {
                        ring_reset();
                        rendered_samples=0;
#if SSI263_R7_ATTACK_US > 0u
                        ssi263_audio_edges_rearm(&edges);
#endif
                        silent_samples=0u;
                        idle_fastpath=false;
                    }
                }
            }
            if(event_count>burst)continue;
        }
        if(fault) {
            // Preserve Apple-visible bus operation, but never emit audio
            // from an unknown/dropped phoneme sequence.
            ring_reset();
            active=false;
            silent_samples=0u;idle_fastpath=false;
            if(read16(status_buf+14)==0)
                fault=false; // clear after reset; next CTL re-arms speech
            vTaskDelay(pdMS_TO_TICKS(5));
            continue;
        }
        const unsigned buffered=(unsigned)read16(status_buf+4);
        const unsigned free_space=(unsigned)read16(status_buf+6);
        if(active && buffered<TARGET_BUFFER &&
           free_space>=BLOCK_SAMPLES) {
            uint64_t begin=bflb_mtimer_get_time_us();
            if(idle_fastpath && ssi263_request(chip)) {
                /* Safe only after >=2.5s of exact PCM16 zeros and model
                 * A/R asserted. Advance model time, but don't synthesize
                 * a sample-by-sample idle waveform. This saves MCU FPU
                 * cycles; it does NOT yet save SPI bytes. */
                ssi263_skip(chip,(real)BLOCK_SAMPLES/(real)pcm_hz);
                memset(signed_samples,0,sizeof(signed_samples));
                ++idle_blocks;
            } else {
                idle_fastpath=false;
                long count=ssi263_run(chip,BLOCK_SAMPLES,float_samples);
                if(count!=BLOCK_SAMPLES) {
                    fault=true;
                    continue;
                }
                ssi_pcm16(float_samples,BLOCK_SAMPLES,
                          params.output_gain,signed_samples);
                /* Unlike an input-write timeout, this can never mute a
                 * sustained nonzero vowel, breath or fricative. */
                bool all_zero=true;
                for(unsigned j=0;j<BLOCK_SAMPLES;j++)
                    if(signed_samples[j]!=0) { all_zero=false; break; }
                /* Carrier quiet A/B must not also activate the R7 fast idle
                 * reset/skip path, which would confound the audio comparison. */
                if(!SSI263_R9B_CARRIER_QUIET_TEST && all_zero && ssi263_request(chip)) {
                    if(silent_samples<idle_zero_samples)
                        silent_samples+=BLOCK_SAMPLES;
                    if(silent_samples>=idle_zero_samples)
                        idle_fastpath=true;
                } else {
                    silent_samples=0u;
                }
            }
            /* Request is a model status indicator, NOT proof of silence. */
            if(ssi263_request(chip))++r9_ar_blocks;
            uint32_t block_raw_peak=0;
            for(unsigned j=0;j<BLOCK_SAMPLES;j++) {
                int32_t s=signed_samples[j];
                uint32_t magnitude=(uint32_t)(s<0 ? -s : s);
                if(magnitude>block_raw_peak)block_raw_peak=magnitude;
            }
            if(block_raw_peak>r9_raw_peak)r9_raw_peak=block_raw_peak;
            if(block_raw_peak<=256u) {
                ++r9_low_blocks;
                if(block_raw_peak>r9_low_peak)r9_low_peak=block_raw_peak;
            }
            for(unsigned j=0;j<BLOCK_SAMPLES;j++) {
                /* R9B: truly bypass the post-PCM attack envelope at 0us. */
                int16_t shaped;
#if SSI263_R7_ATTACK_US > 0u
                shaped=ssi263_audio_edges_sample(&edges,signed_samples[j]);
#else
                shaped=signed_samples[j];
#endif
                int32_t s=shaped;
                uint32_t magnitude=(uint32_t)(s<0 ? -s : s);
                if(magnitude>r9_post_peak)r9_post_peak=magnitude;
                uint16_t v=(uint16_t)shaped;
                pcm_buf[j*2]=(uint8_t)v;
                pcm_buf[j*2+1]=(uint8_t)(v>>8);
            }
            uint64_t end_model=bflb_mtimer_get_time_us();
            fpga_spi_xfer_write(SSI_PCM_SPACE,0,pcm_buf,BLOCK_BYTES);
            uint64_t end_spi=bflb_mtimer_get_time_us();
            uint32_t model_us=(uint32_t)(end_model-begin);
            uint32_t spi_us=(uint32_t)(end_spi-end_model);
            uint32_t total_us=(uint32_t)(end_spi-begin);
            if(model_us>peak_model_us)peak_model_us=model_us;
            if(spi_us>peak_spi_us)peak_spi_us=spi_us;
            ++total_blocks;
            rendered_samples+=BLOCK_SAMPLES;
            /* 128 samples: 2.902/5.805/11.610 ms at div 1/2/4.
             * Scale the prior 2.5 ms guard with the source rate so SLOW
             * means comparable headroom across all three modes. */
            if(total_us>2500u*pcm_rate_div)++slow_blocks;
            if(total_us>block_budget_us)++over_budget_blocks;
        } else {
            // Yield voluntarily even under high-priority audio service;
            // leave USB/SD/virtual-disk network firmware responsive.
            vTaskDelay(pdMS_TO_TICKS(1));
        }
        uint32_t ms=(uint32_t)bflb_mtimer_get_time_ms();
        if((uint32_t)(ms-last_report_ms)>=report_interval_ms) {
            uint32_t elapsed_ms=(uint32_t)(ms-last_report_ms);
            uint32_t window_blocks=total_blocks-prev_blocks;
            uint32_t window_over=over_budget_blocks-prev_over_budget;
            uint32_t rate=elapsed_ms ?
                (uint32_t)((uint64_t)window_blocks*BLOCK_SAMPLES*1000u/
                           elapsed_ms) : 0;
            last_report_ms=ms;
            prev_blocks=total_blocks;
            prev_over_budget=over_budget_blocks;
            // Keep lines below 39 columns; old format cut SEQGAP off.
            osd_log("P10 B=%lu S=%lu G=%lu",
                    (unsigned long)total_blocks,
                    (unsigned long)slow_blocks,
                    (unsigned long)late_events);
            osd_log("P10 RATE=%lu/S OVR=%lu FIFO=%u",
                    (unsigned long)rate,
                    (unsigned long)window_over,
                    (unsigned)read16(status_buf+4));
            osd_log("P10 CPU=%luUS SPI=%luUS UND=%lu",
                    (unsigned long)peak_model_us,
                    (unsigned long)peak_spi_us,
                    (unsigned long)read16(status_buf+10));
            /* Retain legacy R7 field for R8/R9A comparison; E=0 means
             * the edge shaper is disabled, not that no phoneme began. */
#if SSI263_R7_ATTACK_US > 0u
            const unsigned long edge_attacks=(unsigned long)edges.attacks;
#else
            const unsigned long edge_attacks=0ul;
#endif
            osd_log("P10 R7 E=%lu IDLE=%lu Q=%u",
                    edge_attacks,
                    (unsigned long)idle_blocks,
                    (unsigned)idle_fastpath);
            osd_log("R9 RAW=%lu OUT=%lu AR=%lu",
                    (unsigned long)r9_raw_peak,
                    (unsigned long)r9_post_peak,
                    (unsigned long)r9_ar_blocks);
            osd_log("R9 CTL=%02X R4=%02X MODE=%d",
                    (unsigned)ssi263_reg(chip,3),
                    (unsigned)ssi263_reg(chip,4),
                    ssi263_mode(chip));
            osd_log("R9 LOW=%lu PK=%lu TH=256",
                    (unsigned long)r9_low_blocks,
                    (unsigned long)r9_low_peak);
            r9_ar_blocks=0;r9_low_blocks=0;
            r9_raw_peak=0;r9_post_peak=0;r9_low_peak=0;
            peak_model_us=0;
            peak_spi_us=0;
            (void)rendered_samples;(void)last_stamp;
        }
    }
}
