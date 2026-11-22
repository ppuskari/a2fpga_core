/*
 * M1 BL616 ROMless Apple IIe/IIgs media mailbox service.
 * Device I/O: physical slot 3, $C0B0-$C0BF. No peripheral ROM/IRQ.
 *
 * This phase provides actual Apple->MCU FIFO transfer, complete commands,
 * status/stop/replay control, on-console diagnostics and MCU-only loopback.
 * Apple bytes are CHECKSUMMED but NOT passed to HxCMOD yet. That will be
 * M2, after the slot-3 bus decode is proved on both machines.
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "FreeRTOS.h"
#include "task.h"
#include "fpga_spi.h"
#include "osd_console.h"
#include "mcu_mod_audio.h"
#include "disk.h"
#include <ctype.h>
#include "media_mailbox.h"

#define MB_STATUS_ADDR         0x800000u
#define MB_ACK_ADDR            0x800010u
#define MB_RESULT_ADDR         0x800011u
#define MB_MCU_STATUS_ADDR     0x800012u
#define MB_RESET_ADDR          0x800013u
#define MB_INJECT_CMD_ADDR     0x800020u
#define MB_INJECT_BYTE_ADDR    0x800021u

#define MB_STATUS_LEN          31u
#define MB_REPLY_PUSH_ADDR      0x800030u
#define MB_REPLY_RESET_ADDR     0x800031u
#define M2_PATH_MAX             128u
#define M2_ENTRY_MAX             63u
#define AM_DIR_BIT              0x10u
#define MB_RX_CHUNK            32u
#define MB_F_READY             (1u<<0)
#define MB_F_CMD_PENDING       (1u<<2)

static media_mailbox_info_t s_info;
static volatile uint32_t s_probe_requested;
static volatile uint32_t s_selftest_requested;
static uint8_t s_rx[MB_RX_CHUNK];
static uint32_t s_received;
static uint32_t s_expected;
static uint8_t s_xor;
static bool s_test_active;
static uint8_t s_mcu_status_sent=0xFFu;
static bool s_prev_online;

void media_mailbox_get_info(media_mailbox_info_t *dst)
{
    if(dst)memcpy(dst,&s_info,sizeof(*dst));
}
void media_mailbox_request_probe(void)
{
    __atomic_store_n(&s_probe_requested,1u,__ATOMIC_RELEASE);
}
void media_mailbox_request_selftest(void)
{
    __atomic_store_n(&s_selftest_requested,1u,__ATOMIC_RELEASE);
}

static void mb_write(uint32_t addr,uint8_t v)
{
    fpga_spi_xfer_write(MEDIA_SPACE,addr,&v,1u);
}
static uint16_t mb_u16(const uint8_t *p)
{
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1]<<8));
}
static uint32_t mb_u32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1]<<8) |
           ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24);
}

/* M2 request accumulator: active only after ARM ACK; disk task owns FatFS. */
static bool s_m2_hw, s_m2_armed, s_m2_req_overflow, s_m2_directory_open;
static uint8_t s_m2_req[M2_PATH_MAX];
static unsigned s_m2_req_len;
static void m2_reply_reset(void) { mb_write(MB_REPLY_RESET_ADDR,0xA5u); }
static void m2_reply_byte(uint8_t b) { mb_write(MB_REPLY_PUSH_ADDR,b); }
/* Relative paths only, including "" for FAT volume root. */
static const char *m2_path(void)
{
    if(!s_m2_armed || s_m2_req_overflow || !s_m2_req_len ||
       s_m2_req_len>=M2_PATH_MAX ||
       s_m2_req[s_m2_req_len-1]!=0) return NULL;
    for(unsigned i=0;i+1<s_m2_req_len;i++)
        if(s_m2_req[i]<32u || s_m2_req[i]>126u)
            return NULL;  /* embedded NUL/control chars */
    const char *p=(const char *)s_m2_req;
    if(p[0]=='/' || strstr(p,"..") || strchr(p,':') ||
       strchr(p,'\\')) return NULL;
    return p;
}
static uint8_t m2_dir_open(void)
{
    const char *path=m2_path();
    s_m2_armed=false;
    if(!path)return MEDIA_RESULT_M2_BAD_PATH;
    fs_req_t r;
    memset(&r,0,sizeof(r));
    r.op=FSOP_MEDIA_LIST_OPEN;r.path=path;
    const int result=disk_fs_request(&r);
    s_m2_directory_open=(result==0);
    return result==0 ? MEDIA_RESULT_OK:MEDIA_RESULT_M2_FS;
}
static uint8_t m2_dir_next(void)
{
    if(!s_m2_directory_open)return MEDIA_RESULT_M2_NOT_OPEN;
    fs_req_t r;
    for(unsigned i=0;i<4096u;i++) {
        memset(&r,0,sizeof(r));r.op=FSOP_MEDIA_LIST_NEXT;
        if(disk_fs_request(&r)!=0)return MEDIA_RESULT_M2_FS;
        if(!r.name[0])return MEDIA_RESULT_M2_EOF;
        const size_t n=strlen(r.name);
        if(n>M2_ENTRY_MAX || n==0 || strchr(r.name,'/') ||
           strchr(r.name,'\\') || r.name[0]=='.')continue;
        const bool dir=(r.attr & AM_DIR_BIT)!=0u;
        if(!dir) {
            if(n<5u || r.name[n-4]!='.' ||
               tolower((unsigned char)r.name[n-3])!='m' ||
               tolower((unsigned char)r.name[n-2])!='o' ||
               tolower((unsigned char)r.name[n-1])!='d')
                continue;
        }
        m2_reply_reset();
        // Reply frame [length=1+namebytes][kind:1=directory][name ASCII].
        m2_reply_byte((uint8_t)(n+1u));
        m2_reply_byte(dir ? 1u:0u);
        for(size_t j=0;j<n;j++)m2_reply_byte((uint8_t)r.name[j]);
        return MEDIA_RESULT_OK;
    }
    return MEDIA_RESULT_M2_FS;
}
static uint8_t m2_dir_close(void)
{
    fs_req_t r;
    memset(&r,0,sizeof(r));r.op=FSOP_MEDIA_LIST_CLOSE;
    const int result=disk_fs_request(&r);
    s_m2_directory_open=false;
    return result==0 ? MEDIA_RESULT_OK:MEDIA_RESULT_M2_FS;
}
static uint8_t m2_play_or_start(bool jukebox)
{
    const char *path=m2_path();
    s_m2_armed=false;
    if(!path)return MEDIA_RESULT_M2_BAD_PATH;
    const bool accepted=jukebox ?
          mod_audio_jukebox_start_from_file(path):mod_audio_choose(path);
    return accepted ? MEDIA_RESULT_OK:MEDIA_RESULT_M2_BAD_PATH;
}

static void mb_log_status(void)
{
    if(!s_info.online){
        osd_log("M1 SLOT3 $C0B0-BF: FPGA NOT FOUND");
        return;
    }
    osd_log("M1 ROMLESS SLOT3: PROTO1 READY=%u",
            (unsigned)(s_info.flags & MB_F_READY));
    osd_log("M1 A2 RD=%u WR=%u RX=%u FREE=%u",
            (unsigned)s_info.apple_reads,
            (unsigned)s_info.apple_writes,
            (unsigned)s_info.queued,(unsigned)s_info.free_bytes);
    osd_log("M1 CMD=%02X SEQ=%02X ACK=%02X RC=%02X",
            (unsigned)s_info.command,(unsigned)s_info.sequence,
            (unsigned)s_info.acknowledged,(unsigned)s_info.result);
    osd_log("M1 BYTES=%lu XOR=%02X OVF=%u",
            (unsigned long)s_received,(unsigned)s_xor,
            (unsigned)s_info.overflows);
}

static void mb_drain(uint16_t remaining)
{
    while(remaining){
        const uint16_t n=(remaining>MB_RX_CHUNK)?MB_RX_CHUNK:remaining;
        // XFER7 stream read pops n Apple bytes, one per read strobe.
        fpga_spi_xfer_read(MEDIA_SPACE,0,s_rx,n);
        if(s_test_active){
            for(uint16_t j=0;j<n;j++)s_xor^=s_rx[j];
            s_received+=(uint32_t)n;
        } else if(s_m2_armed) {
            for(uint16_t j=0;j<n;j++) {
                if(s_m2_req_len<sizeof(s_m2_req))
                    s_m2_req[s_m2_req_len++]=s_rx[j];
                else
                    s_m2_req_overflow=true;
            }
        }
        remaining-=n;
    }
}

static uint8_t mb_handle_cmd(uint8_t cmd)
{
    switch(cmd){
    case MEDIA_CMD_PING:
        return MEDIA_RESULT_PONG;
    case MEDIA_CMD_REPLAY_LAST:
        return mod_audio_replay_last()?MEDIA_RESULT_OK:
               MEDIA_RESULT_NO_SONG;
    case MEDIA_CMD_STOP:
        mod_audio_request_stop();
        return MEDIA_RESULT_OK;
    case MEDIA_CMD_JUKE_FOLDER:
        mod_audio_jukebox_from_last(false);
        return MEDIA_RESULT_OK;
    case MEDIA_CMD_JUKE_TREE:
        mod_audio_jukebox_from_last(true);
        return MEDIA_RESULT_OK;
    case MEDIA_CMD_NEXT:
        return mod_audio_next()?MEDIA_RESULT_OK:MEDIA_RESULT_NO_SONG;
    case MEDIA_CMD_PREVIOUS:
        return mod_audio_previous()?MEDIA_RESULT_OK:MEDIA_RESULT_NO_SONG;
    case MEDIA_CMD_PLAY_ONCE:
        mod_audio_set_play_once(true);
        return MEDIA_RESULT_OK;
    case MEDIA_CMD_REPEAT_ONE:
        mod_audio_set_play_once(false);
        return MEDIA_RESULT_OK;
    case MEDIA_CMD_BEGIN_TEST:
        s_received=0u;s_xor=0u;
        s_test_active=true;
        return MEDIA_RESULT_OK;
    case MEDIA_CMD_END_TEST:
        if(!s_test_active)return MEDIA_RESULT_NO_BEGIN;
        s_test_active=false;
        if(s_expected!=0u && s_received!=s_expected)
            return MEDIA_RESULT_LENGTH;
        return MEDIA_RESULT_OK;
    case MEDIA_CMD_ABORT_TEST:
        s_test_active=false;
        s_received=0u;s_xor=0u;
        return MEDIA_RESULT_OK;
    default:
        return MEDIA_RESULT_UNKNOWN;
    }
}

/* Perform exactly one bounded SPI polling service pass.
 * cmd BEGIN must execute BEFORE draining, cmd END AFTER draining. */
static bool mb_service_once(void)
{
    uint8_t s[MB_STATUS_LEN];
    fpga_spi_xfer_read(MEDIA_SPACE,MB_STATUS_ADDR,s,sizeof(s));
    if(s[0]!=0x4Du || s[1]!=0x42u || s[2]!=0x01u){
        s_info.online=false;
        return false;
    }
    s_info.online=true;
    s_m2_hw=(s[0x1d]==0x4du && s[0x1e]==0x32u);
    s_info.flags=s[3];
    s_info.command=s[4];
    s_info.free_bytes=mb_u16(s+6);
    s_info.queued=mb_u16(s+8);
    s_info.sequence=s[10];
    s_info.acknowledged=s[11];
    s_info.result=s[12];
    s_info.overflows=mb_u16(s+13);
    s_info.apple_reads=mb_u16(s+0x12);
    s_info.apple_writes=mb_u16(s+0x14);
    s_info.expected_len=mb_u32(s+0x16);

    const bool cmd_pending=(s[3] & MB_F_CMD_PENDING)!=0u;
    const uint8_t cmd=s[4],seq=s[10];
    if(cmd_pending && cmd==MEDIA_CMD_BEGIN_TEST)
        s_expected=s_info.expected_len;
    if(cmd_pending && cmd==MEDIA_CMD_BEGIN_TEST)
        (void)mb_handle_cmd(cmd);

    // Always empty the FIFO: a stale/aborted Apple transfer cannot block
    // another new transfer. Store only the diagnostic count and XOR in M1.
    mb_drain(s_info.queued);

    if(cmd_pending){
        const uint8_t result=(cmd==MEDIA_CMD_BEGIN_TEST)?
                              MEDIA_RESULT_OK:mb_handle_cmd(cmd);
        mb_write(MB_RESULT_ADDR,result);
        mb_write(MB_ACK_ADDR,seq);  // only matching sequence clears pending
        s_info.result=result;
        s_info.acknowledged=seq;
        s_info.flags&=(uint8_t)~MB_F_CMD_PENDING;
        if(cmd==MEDIA_CMD_BEGIN_TEST || cmd==MEDIA_CMD_END_TEST ||
           cmd==MEDIA_CMD_ABORT_TEST)
            osd_log("M1 CMD %02X: RC %02X BYTES %lu",
                    (unsigned)cmd,(unsigned)result,
                    (unsigned long)s_received);
    }

    const uint8_t mcu_flags=(uint8_t)(0x01u |
        ((mod_audio_status()==MOD_PCM_PLAYING)?0x02u:0u) |
        (s_test_active?0x04u:0u));
    if(s_mcu_status_sent!=mcu_flags){
        mb_write(MB_MCU_STATUS_ADDR,mcu_flags);
        s_mcu_status_sent=mcu_flags;
    }
    s_info.received=s_received;
    s_info.xor8=s_xor;
    s_info.test_active=s_test_active;
    return true;
}

static void mb_selftest(void)
{
    if(!s_info.online || s_info.queued ||
       (s_info.flags & MB_F_CMD_PENDING) || s_test_active){
        osd_log("M1 SELFTEST: BUSY/OFFLINE");
        return;
    }
    mb_write(MB_RESET_ADDR,0xA5u);
    // The exact same FPGA command latch and byte FIFO used by POKE.
    mb_write(MB_INJECT_CMD_ADDR,MEDIA_CMD_BEGIN_TEST);
    if(!mb_service_once()){osd_log("M1 SELFTEST: BEGIN FAIL");return;}
    static const uint8_t pattern[8]=
        {0x00u,0x01u,0x23u,0x45u,0x67u,0x89u,0xABu,0xCDu};
    uint8_t expected_xor=0;
    for(unsigned i=0;i<sizeof pattern;i++){
        mb_write(MB_INJECT_BYTE_ADDR,pattern[i]);
        expected_xor^=pattern[i];
    }
    if(!mb_service_once()){osd_log("M1 SELFTEST: FIFO FAIL");return;}
    mb_write(MB_INJECT_CMD_ADDR,MEDIA_CMD_END_TEST);
    if(!mb_service_once()){osd_log("M1 SELFTEST: END FAIL");return;}
    if(!mb_service_once()){osd_log("M1 SELFTEST: READBACK FAIL");return;}
    if(s_info.result==MEDIA_RESULT_OK && s_received==sizeof pattern &&
       s_xor==expected_xor && !s_test_active && !s_info.queued)
        osd_log("M1 SELFTEST PASS 8B XOR=%02X",
                (unsigned)expected_xor);
    else
        osd_log("M1 SELFTEST FAIL N=%lu XOR=%02X R=%02X",
                (unsigned long)s_received,(unsigned)s_xor,
                (unsigned)s_info.result);
}

void media_mailbox_task(void *arg)
{
    (void)arg;
    for(;;){
        const bool online=mb_service_once();
        if(online && !s_prev_online)
            osd_log("M1 ROMLESS MEDIA: SLOT3 SPI7 READY");
        if(!online && s_prev_online)
            osd_log("M1 MEDIA: FPGA MAILBOX LOST");
        s_prev_online=online;

        if(__atomic_exchange_n(&s_probe_requested,0u,__ATOMIC_ACQ_REL))
            mb_log_status();
        if(__atomic_exchange_n(&s_selftest_requested,0u,__ATOMIC_ACQ_REL))
            mb_selftest();

        vTaskDelay(pdMS_TO_TICKS(10));
    }
}
