/*
 * FPGA Screen — OSD text output via SDRAM XFER writes.
 *
 * SDRAM address mapping (from PicoSOC a2mem.c):
 *   PicoSOC 0x04020800 = SDRAM byte 0x020800 (OSD text page)
 *
 * Address encoding (Apple II interleaved text page):
 *   addr = 0x020800 + (0x50 * (y >> 3)) + ((y & 0x07) << 8) + (x << 1)
 *
 * Characters occupy even byte addresses (x<<1); odd bytes are padding.
 * Characters are stored as Apple II screen codes: ASCII + 128 for normal text.
 * Advanced MCU console uses the same 2 KiB page in 80-column layout,
 * with all 80 byte lanes populated (four screen codes per 32-bit word).
 * The M3 TEXT80 pipeline reads each word on-screen as byte lanes 1,0,3,2,
 * so wide writes pre-swap adjacent character bytes to display them in order.
 * v1 simplification: cursor wraps to top (no scroll).
 *
 * IMPORTANT: Characters must be written in batches (one contiguous XFER per
 * screen line) rather than individual single-byte XFERs. The FPGA's SDRAM
 * write accumulator collects bytes into 32-bit words before flushing; when a
 * new write targets a different word and the SDRAM port is busy, the old
 * word is silently dropped. Contiguous batch writes hit the auto-flush path
 * at every 4th byte, keeping the accumulator in sync.
 */

#include <string.h>
#include "fpga_screen.h"
#include "fpga_spi.h"

#define OSD_BASE  0x020800
#define OSD_SIZE  2048
#define SCREEN_W  FPGA_SCREEN_W
#define SCREEN_MAX_W FPGA_SCREEN_WIDE_W
#define SCREEN_H  FPGA_SCREEN_H

static int cursor_h = 0;
static int cursor_v = 0;
static unsigned s_columns = SCREEN_W;
static bool inverse_mode = false;

/* Shadow of the text page (screen codes, no padding bytes) so other
 * subsystems (host build: the telnet menu mirror) can render the current
 * screen without SDRAM read-back. gen bumps on every visible change. */
static uint8_t s_shadow[SCREEN_H][SCREEN_MAX_W];
static volatile uint32_t s_shadow_gen;

const uint8_t *fpga_screen_shadow_row(int y)
{
    return s_shadow[(y < 0 || y >= SCREEN_H) ? 0 : y];
}

uint32_t fpga_screen_shadow_gen(void)
{
    return s_shadow_gen;
}

static void shadow_set(int x, int y, uint8_t code)
{
    if (x >= 0 && (unsigned)x < s_columns && y >= 0 && y < SCREEN_H)
        s_shadow[y][x] = code;
}

void fpga_screen_set_columns(unsigned columns)
{
    if (columns != SCREEN_W && columns != SCREEN_MAX_W)
        return;
    s_columns = columns;
    cursor_h = 0;
    cursor_v = 0;
    ++s_shadow_gen;
}

unsigned fpga_screen_columns(void)
{
    return s_columns;
}

/* ASCII -> Apple II screen code. Normal text = ASCII+128; inverse = codes
 * $00-$3F (uppercase + symbols only, so lowercase is folded to uppercase). */
static uint8_t screen_code(uint8_t c)
{
    if (c >= 'a' && c <= 'z')
        c -= 32;
    if (inverse_mode) {
        if (c >= 0x40 && c < 0x60)
            return (uint8_t)(c - 0x40);   /* @A-Z... -> $00-$1F */
        if (c >= 0x20 && c < 0x40)
            return c;                     /* space/digits/symbols -> $20-$3F */
        return 0x20;                      /* out of range: inverse space */
    }
    return (uint8_t)(c + 128);
}

static uint32_t screen_addr(int x, int y)
{
    return OSD_BASE + (0x50 * (y >> 3)) + ((y & 0x07) << 8) +
           ((s_columns == SCREEN_W) ? (x << 1) : x);
}

void fpga_screen_clear(void)
{
    fpga_spi_xfer_fill(FPGA_SPACE_SDRAM, OSD_BASE, 0xA0, OSD_SIZE);
    cursor_h = 0;
    cursor_v = 0;
    memset(s_shadow, 0xA0, sizeof(s_shadow));
    s_shadow_gen++;
}

static void newline(void)
{
    cursor_h = 0;
    cursor_v++;
    if (cursor_v >= SCREEN_H) {
        cursor_v = 0;  /* Wrap to top (no scroll in v1) */
    }
}

/* Flush a run of characters as one contiguous XFER write.
 * buf[] has characters at even offsets and 0xA0 padding at odd offsets.
 * This hits the SDRAM accumulator's auto-flush every 4 bytes, avoiding
 * the lost-word race when the port is busy. */
static void flush_line(int start_h, int start_v, const uint8_t *buf, int nbytes)
{
    if (nbytes <= 0)
        return;
    if (s_columns == SCREEN_W) {
        /* Preserve the established 40-column char/pad pairs. */
        fpga_spi_xfer_write(FPGA_SPACE_SDRAM,
                            screen_addr(start_h, start_v),
                            buf, (uint16_t)nbytes);
    } else {
        /* In 80-column mode, do not leave partial 32-bit SDRAM writes.
         * Reconstruct the touched aligned words from the SRAM shadow.
         * An isolated character update must not overwrite its neighbors. */
        const int first = start_h & ~3;
        int end = (start_h + nbytes + 3) & ~3;
        if (end > SCREEN_MAX_W)
            end = SCREEN_MAX_W;
        uint8_t packed[SCREEN_MAX_W];
        const int count = end - first;
        /* M3 apple_video_gen TEXT80 fetch/ROM pipeline outputs each 4-byte
         * group as lanes 1,0,3,2 (LSB-first pixel shifter, 2-cycle ROM).
         * Store adjacent logical characters in REVERSED physical lanes to
         * compensate. Without this, 'DISK' appears as 'IDKS' on HDMI even
         * though a naive SDRAM readback test passes.
         *
         * Keep the shadow and Telnet mirror in normal, logical left-to-right
         * order. Only encode the packed 80-column SDRAM write differently.
         * first is always 4-byte aligned so XOR 1 never escapes the word.
         * Do NOT change the proven 40-column main/aux packing path. */
        for (int i = 0; i < count; ++i)
            packed[i] = s_shadow[start_v][first + (i ^ 1)];
        fpga_spi_xfer_write(FPGA_SPACE_SDRAM,
                            screen_addr(first, start_v),
                            packed, (uint16_t)count);
    }
}

void fpga_screen_putchar(uint8_t c)
{
    if (c == '\n') {
        newline();
        return;
    }
    if (c < 32) return;

    /* Single char: write 2 bytes (char + padding) so the SDRAM accumulator
     * sees a complete even/odd pair, reducing flush race likelihood. */
    uint8_t pair[2] = { screen_code(c), 0xA0 };
    shadow_set(cursor_h, cursor_v, pair[0]);
    if (s_columns == SCREEN_W) {
        fpga_spi_xfer_write(FPGA_SPACE_SDRAM,
                            screen_addr(cursor_h, cursor_v), pair, 2);
    } else {
        flush_line(cursor_h, cursor_v, pair, 1);
    }
    s_shadow_gen++;

    cursor_h++;
    if ((unsigned)cursor_h >= s_columns) {
        newline();
    }
}

void fpga_screen_puts(const char *str)
{
    /* Build contiguous buffer for each screen line: character at even byte,
     * 0xA0 padding at odd byte. Write entire line as one XFER. */
    uint8_t buf[SCREEN_MAX_W * 2];
    int count = 0;
    int start_h = cursor_h;
    int start_v = cursor_v;

    while (*str) {
        uint8_t c = (uint8_t)*str++;

        if (c == '\n' || c < 32) {
            flush_line(start_h, start_v, buf, count);
            count = 0;
            if (c == '\n') newline();
            start_h = cursor_h;
            start_v = cursor_v;
            continue;
        }

        const uint8_t code = screen_code(c);
        buf[count++] = code;
        if (s_columns == SCREEN_W)
            buf[count++] = 0xA0; /* 40-column odd-byte padding only */
        shadow_set(cursor_h, cursor_v, code);

        cursor_h++;
        if ((unsigned)cursor_h >= s_columns) {
            flush_line(start_h, start_v, buf, count);
            count = 0;
            newline();
            start_h = cursor_h;
            start_v = cursor_v;
        }
    }

    flush_line(start_h, start_v, buf, count);
    s_shadow_gen++;
}

void fpga_screen_home(void)
{
    cursor_h = 0;
    cursor_v = 0;
}

void fpga_screen_goto(int x, int y)
{
    if (x < 0) x = 0;
    if (x >= (int)s_columns) x = (int)s_columns - 1;
    if (y < 0) y = 0;
    if (y >= SCREEN_H) y = SCREEN_H - 1;
    cursor_h = x;
    cursor_v = y;
}

void fpga_screen_set_inverse(bool inverse)
{
    inverse_mode = inverse;
}
