/*
 * Runtime MOD PCM transfer to Enhanced DOC wave SDRAM.
 * Each 32-bit word gets a real FPGA->GLU memory ready ack before next word.
 * This is intentionally conservative: correctness first, speed optimization
 * after hardware profiling. No Stage1 flash or original MB code changes.
 */
#include "sensei_pcm_upload.h"
#include "fpga_spi.h"
#include "FreeRTOS.h"
#include "task.h"
#include <stddef.h>

#define P2_SPACE 6u
#define PCM_WORD_MAX 16384u
#define PCM_BYTE_MAX (PCM_WORD_MAX * 4u)

static void spi_write(uint8_t reg,uint8_t data)
{
    fpga_spi_xfer_write(P2_SPACE,reg,&data,1);
}
static void spi_read(uint8_t reg,uint8_t *data,uint16_t size)
{
    fpga_spi_xfer_read(P2_SPACE,reg,data,size);
}
static void abort_upload(void)
{
    spi_write(0x1F,0x00);
}
bool sensei_pcm_upload(const uint8_t *pcm, uint32_t bytes)
{
    uint8_t status[4], signature[2], packet[7], feature;
    uint32_t word_count;
    if (!pcm || !bytes || (bytes&3u) || bytes>PCM_BYTE_MAX)
        return false;

    spi_read(0,signature,2);
    spi_read(0x26,&feature,1);
    if (signature[0]!=0x53 || signature[1]!=0x1D || feature!=0x42)
        return false; /* P1D FPGA has no acknowledged PCM bulk writer */

    word_count=bytes>>2;
    spi_write(0x1F,0xA5);
    spi_read(0x20,status,4);
    if (status[0]!=0x01 || status[1] || status[2] || status[3]) {
        abort_upload();
        return false;
    }

    for(uint32_t i=0;i<word_count;++i) {
        packet[0]=(uint8_t)i;
        packet[1]=(uint8_t)(i>>8);
        packet[2]=pcm[i*4u+0u];
        packet[3]=pcm[i*4u+1u];
        packet[4]=pcm[i*4u+2u];
        packet[5]=pcm[i*4u+3u];
        packet[6]=0xA5;
        fpga_spi_xfer_write(P2_SPACE,0x18,packet,sizeof(packet));

        // No backpressure exists on the upstream bytewise SPI transport.
        // One outstanding 32-bit write at a time, with an explicit ACK.
        bool acknowledged=false;
        for(unsigned tries=0;tries<250u;++tries) {
            uint16_t count;
            spi_read(0x20,status,4);
            count=(uint16_t)status[1]|((uint16_t)status[2]<<8);
            if ((status[0]&4u) || status[3]) break;
            if (count==(uint16_t)(i+1u) && !(status[0]&2u)) {
                acknowledged=true;
                break;
            }
            if (tries%10u==9u) vTaskDelay(pdMS_TO_TICKS(1));
        }
        if (!acknowledged) {
            abort_upload();
            return false;
        }
    }

    spi_write(0x1F,0x5A);
    spi_read(0x20,status,4);
    if (status[0]!=0x08 || status[3] ||
        (((uint16_t)status[1]|((uint16_t)status[2]<<8))!=word_count)) {
        abort_upload();
        return false;
    }
    return true;
}
