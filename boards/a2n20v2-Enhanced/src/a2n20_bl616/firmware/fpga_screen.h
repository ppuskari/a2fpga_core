/*
 * FPGA Screen — OSD text output via SDRAM XFER writes.
 * Same text page and address encoding as PicoSOC a2mem.c.
 */

#ifndef _FPGA_SCREEN_H
#define _FPGA_SCREEN_H

#include <stdbool.h>
#include <stdint.h>

#define FPGA_SCREEN_W 40         /* Existing menu width */
#define FPGA_SCREEN_WIDE_W 80    /* Advanced MCU console width */
#define FPGA_SCREEN_H 24

/* Select 40 or 80 columns for subsequent OSD writes. The corresponding
 * FPGA COL80 register is owned by the menu/console view controller.
 * Does not alter the live Apple II video mode when MCU overlay is hidden. */
void fpga_screen_set_columns(unsigned columns);
unsigned fpga_screen_columns(void);

/* Clear the selected 40/80-column text screen (fill with 0xA0 = space) */
void fpga_screen_clear(void);

/* Write a single character at the current cursor position */
void fpga_screen_putchar(uint8_t c);

/* Write a null-terminated string */
void fpga_screen_puts(const char *str);

/* Reset cursor to (0, 0) */
void fpga_screen_home(void);

/* Move the cursor (clamped to the screen) */
void fpga_screen_goto(int x, int y);

/* Inverse-video mode for subsequent putchar/puts (Apple II screen codes
 * $00-$3F). Lowercase is uppercased; only uppercase/digits/symbols render. */
void fpga_screen_set_inverse(bool inverse);

/* Shadow of the 80x24 maximum text page (Apple II screen codes); a 40-col
 * menu uses the first 40 entries. The remote mirror queries current width. */
const uint8_t *fpga_screen_shadow_row(int y);
uint32_t       fpga_screen_shadow_gen(void);

#endif
