/* M2 MCU FAT request/reply integration (real media_mailbox.c, fake SPI7).
 * Regression gate: M1 commands remain intact, MCU path validation, per-client
 * FatFS cursor, .MOD filter, M2 reply framing, start-at-selected-file action.
 */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <stdlib.h>
#include "fpga_spi.h"
#include "disk.h"
#include "mcu_mod_audio.h"
#include "mcu_mod_now_playing.h"
#include "osd_console.h"
#include "FreeRTOS.h"
#include "task.h"

static uint8_t upload[256],response[256];
static unsigned upload_head,upload_count,response_count;
static uint8_t fake_cmd,fake_seq,fake_ack,fake_result;
static bool pending;
static bool fake_hw=true,fake_usb;
static bool media_dir_open, stress_mode;
static unsigned fs_cursor,open_calls,close_calls,play_calls,juke_calls,stop_calls;
static char last_open[128],last_play[128],last_juke[128];
static bool now_playing_active=true, now_snapshot_valid=true;
static char now_playing_path[128]="MUSIC/CLASSICS/CHEER.MOD";
bool mod_now_playing_snapshot(mod_now_playing_t *out)
{
    if(!now_snapshot_valid)return false;
    memset(out,0,sizeof(*out));
    out->active=now_playing_active;
    if(now_playing_active)
        snprintf(out->path,sizeof out->path,"%s",now_playing_path);
    return true;
}
#define CHECK(v) do{ if(!(v)){fprintf(stderr,"FAIL M2 line %d: %s\n",__LINE__,#v);exit(1);} }while(0)
void *pvPortMalloc(size_t n) {return malloc(n);}
void vPortFree(void *p) {free(p);}
void vTaskDelay(uint32_t ticks) {(void)ticks;}
void osd_log(const char *fmt,...) {(void)fmt;}
mod_pcm_status_t mod_audio_status(void) {return MOD_PCM_PLAYING;}
unsigned mod_audio_jukebox_last_track(void) {return 3u;}
unsigned mod_audio_jukebox_count(void) {return 41u;}
bool mod_audio_replay_last(void) {return true;}
void mod_audio_request_stop(void) {stop_calls++;}
void mod_audio_jukebox_from_last(bool recursive) {(void)recursive;}
bool mod_audio_next(void) {return true;}
bool mod_audio_previous(void) {return true;}
void mod_audio_set_play_once(bool once) {(void)once;}
bool mod_audio_jukebox_resume(void) {return true;}
bool mod_audio_choose(const char *path) {
    play_calls++;snprintf(last_play,sizeof last_play,"%s",path);return true;
}
bool mod_audio_jukebox_start_from_file(const char *path) {
    juke_calls++;snprintf(last_juke,sizeof last_juke,"%s",path);return true;
}
bool disk_backend_is_usb(void) {return fake_usb;}
int disk_fs_request(fs_req_t *r)
{
    r->out=0;
    switch(r->op) {
    case FSOP_MEDIA_LIST_OPEN:
        open_calls++;
        snprintf(last_open,sizeof last_open,"%s",r->path);
        media_dir_open=true;fs_cursor=0;return 0;
    case FSOP_MEDIA_LIST_CLOSE:
        close_calls++;media_dir_open=false;return 0;
    case FSOP_MEDIA_LIST_NEXT:
        if(!media_dir_open)return -1;
        r->name[0]=0;
        if(stress_mode) {
            if(fs_cursor<28u) {
                snprintf(r->name,sizeof r->name,"TRACK%03u.MOD",27u-fs_cursor);
                r->attr=0;
            }
            fs_cursor++;
            return 0;
        }
        switch(fs_cursor++){
        case 0:snprintf(r->name,sizeof r->name,"ALBUM");r->attr=0x10;break;
        case 1:snprintf(r->name,sizeof r->name,"ignore.mp3");r->attr=0;break;
        case 2:snprintf(r->name,sizeof r->name,"CHEER.MOD");r->attr=0;break;
        case 3:snprintf(r->name,sizeof r->name,"3edges.mod");r->attr=0;break;
        default:break;
        }
        return 0;
    default:return -1;
    }
}
void fpga_spi_xfer_read(uint8_t space,uint32_t addr,uint8_t *dst,uint16_t len)
{
    CHECK(space==7);
    memset(dst,0,len);
    if(addr==0x800000u) {
        CHECK(len==31);
        dst[0]='M';dst[1]='B';dst[2]=1;
        dst[3]=1u | (pending?4u:0u);
        dst[4]=fake_cmd;
        dst[6]=(uint8_t)(256-upload_count);
        dst[7]=(uint8_t)((256-upload_count)>>8);
        dst[8]=(uint8_t)upload_count;
        dst[9]=(uint8_t)(upload_count>>8);
        dst[10]=fake_seq;dst[11]=fake_ack;dst[12]=fake_result;
        dst[29]=fake_hw?'M':0;dst[30]=fake_hw?'2':0;
        return;
    }
    CHECK(addr==0u);
    CHECK(len<=upload_count);
    for(unsigned i=0;i<len;i++)
        dst[i]=upload[(upload_head+i)%256u];
    upload_head=(upload_head+len)%256u;
    upload_count-=len;
}
void fpga_spi_xfer_write(uint8_t space,uint32_t addr,const uint8_t *src,uint16_t len)
{
    CHECK(space==7 && len==1);
    const uint8_t b=src[0];
    switch(addr) {
    case 0x800010:CHECK(b==fake_seq && pending);pending=false;fake_ack=b;break;
    case 0x800011:fake_result=b;break;
    case 0x800012:break;
    case 0x800013:upload_head=0;upload_count=0;break;
    case 0x800030:CHECK(response_count<sizeof response);response[response_count++]=b;break;
    case 0x800031:CHECK(b==0xA5);response_count=0;break;
    case 0x800020:CHECK(!pending);fake_cmd=b;fake_seq++;pending=true;break;
    case 0x800021:CHECK(upload_count<256);upload[(upload_head+upload_count)%256u]=b;upload_count++;break;
    default:fprintf(stderr,"unexpected M2 SPI write $%lX\n",(unsigned long)addr);exit(1);
    }
}
/* Include real source to exercise static mb_service_once(). */
#include "media_mailbox.c"

static uint8_t command(uint8_t cmd)
{
    CHECK(!pending);
    fake_seq++;
    fake_cmd=cmd;
    pending=true;
    CHECK(mb_service_once());
    CHECK(!pending);
    CHECK(fake_ack==fake_seq);
    return fake_result;
}
static void send_bytes(const char *path,bool split)
{
    for(size_t i=0;i<=strlen(path);i++) {
        CHECK(upload_count<256);
        upload[(upload_head+upload_count)%256u]=(uint8_t)path[i];
        upload_count++;
        if(split)CHECK(mb_service_once());
    }
}
static void path_cmd(const char *path,uint8_t cmd,uint8_t expected)
{
    CHECK(command(MEDIA_CMD_M2_ARM)==MEDIA_RESULT_OK);
    send_bytes(path,true);
    CHECK(command(cmd)==expected);
}
int main(void)
{
    CHECK(command(MEDIA_CMD_PING)==MEDIA_RESULT_PONG);
    CHECK(command(MEDIA_CMD_M2_CAPS)==2u);
    fake_hw=false;
    CHECK(command(MEDIA_CMD_M2_CAPS)==MEDIA_RESULT_M2_OLD_FPGA);
    fake_hw=true;
    CHECK(command(MEDIA_CMD_M2_SOURCE)==0);
    CHECK(command(MEDIA_CMD_M2_NOWPLAY)==0);
    CHECK(response_count==11 && response[0]==10 && response[1]==1 &&
          !memcmp(response+2,"CHEER.MOD",9));
    now_playing_active=false;
    CHECK(command(MEDIA_CMD_M2_NOWPLAY)==0);
    CHECK(response_count==2 && response[0]==1 && response[1]==0);
    now_playing_active=true;
    now_snapshot_valid=false;
    CHECK(command(MEDIA_CMD_M2_NOWPLAY)==MEDIA_RESULT_M2_RETRY);
    now_snapshot_valid=true;
    CHECK(response_count==2 && response[0]==1 && response[1]==0);
    CHECK(command(MEDIA_CMD_M2_STATUS)==0);
    CHECK(response_count==6 && response[0]==5 && response[1]==MOD_PCM_PLAYING &&
          response[2]==3 && response[4]==41);
    path_cmd("MODS",MEDIA_CMD_M2_OPEN,MEDIA_RESULT_OK);
    CHECK(!media_dir_open && open_calls==1 && close_calls==1 && !strcmp(last_open,"MODS"));
    CHECK(command(MEDIA_CMD_M2_NEXT)==0);
    CHECK(response_count==7 && response[0]==6 && response[1]==1 &&
          !memcmp(response+2,"ALBUM",5));
    CHECK(command(MEDIA_CMD_M2_NEXT)==0);
    CHECK(response_count==12 && response[0]==11 && response[1]==0 &&
          !memcmp(response+2,"3edges.mod",10));
    CHECK(command(MEDIA_CMD_M2_NEXT)==0);
    CHECK(response_count==11 && response[0]==10 && response[1]==0 &&
          !memcmp(response+2,"CHEER.MOD",9));
    CHECK(command(MEDIA_CMD_M2_NEXT)==MEDIA_RESULT_M2_EOF);
    CHECK(command(MEDIA_CMD_M2_CLOSE)==MEDIA_RESULT_OK);
    CHECK(!media_dir_open && close_calls==1);
    /* Deliberately reverse FAT order across 3 pages. The player and
     * Apple browser must both present TRACK000..TRACK027 alphabetically,
     * regardless of the page size (12), without rescanning between pages. */
    stress_mode=true;
    path_cmd("MODS",MEDIA_CMD_M2_OPEN,MEDIA_RESULT_OK);
    CHECK(open_calls==2 && close_calls==2 && !media_dir_open);
    for(unsigned i=0;i<28u;i++) {
        char expected[32];
        snprintf(expected,sizeof expected,"TRACK%03u.MOD",i);
        CHECK(command(MEDIA_CMD_M2_NEXT)==0);
        CHECK(response_count==14 && response[0]==13 && response[1]==0 &&
              !memcmp(response+2,expected,12));
    }
    CHECK(command(MEDIA_CMD_M2_NEXT)==MEDIA_RESULT_M2_EOF);
    CHECK(command(MEDIA_CMD_M2_CLOSE)==MEDIA_RESULT_OK);
    CHECK(close_calls==2);
    stress_mode=false;
    path_cmd("MODS/CHEER.MOD",MEDIA_CMD_M2_PLAY,MEDIA_RESULT_OK);
    CHECK(play_calls==1 && !strcmp(last_play,"MODS/CHEER.MOD"));
    path_cmd("MODS/3edges.mod",MEDIA_CMD_M2_START,MEDIA_RESULT_OK);
    CHECK(juke_calls==1 && !strcmp(last_juke,"MODS/3edges.mod"));
    CHECK(command(MEDIA_CMD_M2_RESUME)==MEDIA_RESULT_OK);
    path_cmd("../danger",MEDIA_CMD_M2_OPEN,MEDIA_RESULT_M2_BAD_PATH);
    CHECK(open_calls==2); /* no disk requests for traversal */
    CHECK(command(MEDIA_CMD_STOP)==MEDIA_RESULT_OK && stop_calls==1);
    CHECK(command(MEDIA_CMD_PING)==MEDIA_RESULT_PONG);
    printf("PASS M2 real MCU mailbox: globally sorted FAT catalog across 3 pages, file play, start-file\n");
    printf("PASS M2 protocol: M1 compatibility, live now-playing frame, source/status, path validation\n");
    return 0;
}
