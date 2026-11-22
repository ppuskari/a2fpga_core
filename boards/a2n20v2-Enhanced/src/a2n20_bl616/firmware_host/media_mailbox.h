/*
 * ROMless slot-3 A2FPGA Media Mailbox M1. Independent from native IIgs DOC,
 * Mockingboard, SSI263, and the MCU->HDMI PCM stream.
 */
#ifndef A2FPGA_MEDIA_MAILBOX_H
#define A2FPGA_MEDIA_MAILBOX_H
#include <stdbool.h>
#include <stdint.h>

#define MEDIA_SPACE             7u
#define MEDIA_CMD_PING          0x01u
#define MEDIA_CMD_REPLAY_LAST   0x02u
#define MEDIA_CMD_STOP          0x03u
/* J1: no FPGA change; commands use the existing M1 slot-3 latch. */
#define MEDIA_CMD_JUKE_FOLDER   0x04u
#define MEDIA_CMD_JUKE_TREE     0x05u
#define MEDIA_CMD_NEXT          0x06u
#define MEDIA_CMD_PREVIOUS      0x07u
#define MEDIA_CMD_PLAY_ONCE     0x08u
#define MEDIA_CMD_REPEAT_ONE    0x09u
#define MEDIA_CMD_BEGIN_TEST    0x10u
#define MEDIA_CMD_END_TEST      0x11u
#define MEDIA_CMD_ABORT_TEST    0x12u
/* M2 extension: M1+Apple ABI remains protocol=1 for compatibility.
 * CAPS returns 2 only when new M2 FPGA response FIFO is present.
 * Apple write $C0B5 -> request FIFO; Apple read $C0B5 -> reply FIFO.
 * Status $C0B3 bit7: REPLY_READY. Response is [payload_len,type,...].
 * ARM, then push NUL-terminated ASCII relative path, then OPEN/PLAY/START. */
#define MEDIA_CMD_M2_CAPS      0x20u
#define MEDIA_CMD_M2_ARM       0x21u
#define MEDIA_CMD_M2_OPEN      0x22u
#define MEDIA_CMD_M2_NEXT      0x23u
#define MEDIA_CMD_M2_CLOSE     0x24u
#define MEDIA_CMD_M2_PLAY      0x25u
#define MEDIA_CMD_M2_START     0x26u
#define MEDIA_CMD_M2_RESUME    0x27u
#define MEDIA_CMD_M2_SOURCE    0x28u
#define MEDIA_CMD_M2_STATUS    0x29u
/* Current MOD filename: reply [1+n, active, basename ASCII n], n <= 63. */
#define MEDIA_CMD_M2_NOWPLAY   0x2Au
#define MEDIA_RESULT_M2_EOF    0xD0u
#define MEDIA_RESULT_M2_BAD_PATH 0xE6u
#define MEDIA_RESULT_M2_FS     0xE7u
#define MEDIA_RESULT_M2_OLD_FPGA 0xE8u
#define MEDIA_RESULT_M2_NOT_OPEN 0xE9u
#define MEDIA_RESULT_M2_RETRY    0xEAu /* concurrent now-playing snapshot */


#define MEDIA_RESULT_OK         0x00u
#define MEDIA_RESULT_PONG       0xA5u
#define MEDIA_RESULT_NO_SONG    0xE2u
#define MEDIA_RESULT_NO_BEGIN   0xE3u
#define MEDIA_RESULT_LENGTH     0xE4u
#define MEDIA_RESULT_UNKNOWN    0xEFu

typedef struct {
    bool online;
    uint8_t flags, command, sequence, acknowledged, result;
    uint16_t queued, free_bytes, overflows;
    uint16_t apple_reads, apple_writes;
    uint32_t expected_len, received;
    uint8_t xor8;
    bool test_active;
} media_mailbox_info_t;

/* Snapshot is diagnostic-only; one writer in the mailbox service task. */
void media_mailbox_get_info(media_mailbox_info_t *dst);
/* Request a log dump / in-FPGA FIFO loopback from the task, not from UI. */
void media_mailbox_request_probe(void);
void media_mailbox_request_selftest(void);
void media_mailbox_task(void *arg);
#endif
