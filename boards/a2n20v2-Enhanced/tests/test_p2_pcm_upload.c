/* Host simulation of REAL sensei_pcm_upload.c, including SPI6 ack/error.
 * The firmware is not permitted to play if GLU upload doesn't ACK.
 */
#include "sensei_pcm_upload.h"
#include "fpga_spi.h"
#include "FreeRTOS.h"
#include "task.h"
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
static uint8_t ram[512], pending, active, done, err, feature=0x42;
static uint16_t acks,fail_word=0xFFFFu;
static unsigned begin_calls,abort_calls,end_calls;
static void fault(const char *s) {fprintf(stderr,"FAIL P2 uploader: %s\n",s);exit(1);}
void vTaskDelay(uint32_t ms) {(void)ms;}
void fpga_spi_xfer_write(uint8_t space,uint32_t addr,const uint8_t *buf,uint16_t n)
{
    if(space!=6)fault("wrong SPI space");
    if(addr==0x1F && n==1) {
        if(buf[0]==0xA5) {active=1;done=0;err=0;acks=0;begin_calls++;}
        else if(buf[0]==0x5A) {active=0;done=1;end_calls++;}
        else if(buf[0]==0) {active=done=0;abort_calls++;}
        return;
    }
    if(addr==0x18 && n==7 && buf[6]==0xA5) {
        uint16_t word=(uint16_t)buf[0]|((uint16_t)buf[1]<<8);
        if(!active || pending || word!=acks || 4u*(uint32_t)word+4u>sizeof ram)
            fault("wrong word sequence or overrun");
        if(word==fail_word) {err=1;pending=1;return;}
        memcpy(ram+4u*word,buf+2,4);
        acks++;
        return;
    }
    fault("unknown SPI write");
}
void fpga_spi_xfer_read(uint8_t space,uint32_t addr,uint8_t *out,uint16_t n)
{
    if(space!=6)fault("wrong SPI read space");
    memset(out,0,n);
    if(addr==0 && n==2) {out[0]=0x53;out[1]=0x1D;}
    else if(addr==0x26 && n==1)out[0]=feature;
    else if(addr==0x20 && n==4) {
        out[0]=(active?1u:0u)|(pending?2u:0u)|(err?4u:0u)|(done?8u:0u);
        out[1]=(uint8_t)acks;out[2]=(uint8_t)(acks>>8);out[3]=err;
    } else fault("unknown SPI read");
}
int main(void)
{
    uint8_t src[512];
    for(unsigned i=0;i<sizeof src;i++)src[i]=(uint8_t)(i*7u);
    if(!sensei_pcm_upload(src,sizeof src))fault("good PCM upload rejected");
    if(memcmp(src,ram,sizeof src) || acks!=128 || begin_calls!=1 ||
       end_calls!=1 || abort_calls || !done)
       fault("DMA bytes/count/commit disagree");
    puts("PASS P2 uploader: 128 acknowledged words, exact 512-byte DOC PCM image");
    fail_word=10;pending=0;
    if(sensei_pcm_upload(src,64))fault("unacknowledged SDRAM write accepted");
    if(!abort_calls || active || done)fault("DMA failure did not abort safely");
    puts("PASS P2 uploader: stalled/failed memory write rejects playback and aborts");
    feature=0;fail_word=0xFFFFu;
    if(sensei_pcm_upload(src,64))fault("old P1D FPGA accepted without P2 capability");
    puts("PASS P2 uploader: rejects incompatible FPGA");
    return 0;
}
