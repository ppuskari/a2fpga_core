/*
 * P10 SSI263 hybrid audio renderer for BL616 firmware_host.
 *
 * New FPGA XFER space 5: 8B host write event
 *  [addr,data,seq16LE,xck32LE], auto-pop after last byte.
 * XFER space 4 read @0x800000: 24B transport status.
 * XFER space 4 write @0: mono PCM16LE, 44.1 kHz.
 * XFER space 4 write @0x800000: PCM ring reset.
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

#define SSI_PCM_SPACE      4u
#define SSI_EVENTS_SPACE   5u
#define SSI_STATUS_ADDR    0x800000u
#define BLOCK_SAMPLES      128u
#define BLOCK_BYTES        (2u*BLOCK_SAMPLES)
#define EVENTS_PER_BURST   12u
#define STATUS_LEN         24u
#define TARGET_BUFFER      1024u
#define XCK_HZ             1020000.0f

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

/* Log a mismatch without pretending the SSI model is synchronized.
 * If a FIFO overflow occurs the CPU event stream is no longer complete;
 * power-cycle/restart is required for speech accuracy. */
void ssi263_hybrid_task(void *arg)
{
    (void)arg;
    ssi263_params params;
    ssi263_default_params(&params);
    params.xck_hz=XCK_HZ;
    ssi263 *chip=ssi263_new(&params,ssi263_default_rom(),44100.0f);
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

    while(!read_status())vTaskDelay(pdMS_TO_TICKS(100));
    ring_reset();
    osd_log("P10 SSI263: Pico C hybrid online");
    for(;;) {
        if(!read_status()) {
            active=false;seq_valid=false;fault=true;
            vTaskDelay(pdMS_TO_TICKS(20));
            continue;
        }
        const unsigned event_count=(unsigned)read16(status_buf+8);
        if(read16(status_buf+14)!=0)fault=true;
        unsigned burst=event_count>EVENTS_PER_BURST ?
               EVENTS_PER_BURST : event_count;

        if(burst) {
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
            long count=ssi263_run(chip,BLOCK_SAMPLES,float_samples);
            if(count!=BLOCK_SAMPLES) {
                fault=true;
                continue;
            }
            ssi_pcm16(float_samples,BLOCK_SAMPLES,
                      params.output_gain,signed_samples);
            for(unsigned j=0;j<BLOCK_SAMPLES;j++) {
                uint16_t v=(uint16_t)signed_samples[j];
                pcm_buf[j*2]=(uint8_t)v;
                pcm_buf[j*2+1]=(uint8_t)(v>>8);
            }
            fpga_spi_xfer_write(SSI_PCM_SPACE,0,pcm_buf,BLOCK_BYTES);
            ++total_blocks;
            rendered_samples+=BLOCK_SAMPLES;
            if(bflb_mtimer_get_time_us()-begin>2500u)
                ++slow_blocks;
        } else {
            // Yield voluntarily even under high-priority audio service;
            // leave USB/SD/virtual-disk network firmware responsive.
            vTaskDelay(pdMS_TO_TICKS(1));
        }
        uint32_t ms=(uint32_t)bflb_mtimer_get_time_ms();
        if(ms-last_report_ms>=3000u) {
            last_report_ms=ms;
            osd_log("P10 speech blocks=%lu slow=%lu seqgap=%lu fifo=%u",
                    (unsigned long)total_blocks,
                    (unsigned long)slow_blocks,
                    (unsigned long)late_events,
                    (unsigned)read16(status_buf+4));
            (void)rendered_samples;(void)last_stamp;
        }
    }
}
