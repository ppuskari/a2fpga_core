/*
 * osd_console — shared boot/status console for the BL616 host build.
 *
 * Every subsystem (USB host, USB-Ethernet, Disk II, menu) appends one line per
 * STATE CHANGE via osd_log() instead of owning the screen and continuously
 * repainting. Backed by the FPGA OSD text page (fpga_screen) + the
 * video_control_if takeover (reg 0x10 VIDEO_ENABLE, 0x11 TEXT_MODE).
 *
 * Visibility model:
 *   - osd_console_show(): take over the Apple II display, repaint the log.
 *   - osd_console_hide(): hand the display back to the live Apple II.
 *   - osd_log() only writes to an MCU SRAM line ring in BOTH states. It never
 *     repaints the FPGA screen or steals Apple video from real-time audio.
 *   - osd_console_service() runs on the menu/HID task to repaint at <=1 Hz
 *     only while visible; osd_console_show() always paints immediately.
 */
#ifndef _OSD_CONSOLE_H
#define _OSD_CONSOLE_H

#include <stdbool.h>
#include <stdint.h>

/* Console text is 80 columns wide; leave one column clear to prevent
 * auto-wrap followed by our explicit newline. Stored lines include NUL. */
#define OSD_CONSOLE_ROWS 23
#define OSD_CONSOLE_COLS 79
#define OSD_CONSOLE_LINE_CAP (OSD_CONSOLE_COLS + 1)

void osd_log(const char *fmt, ...);   /* append one status line (thread-safe) */
/* MCU menu thread: one buffered FPGA OSD refresh per second, if visible. */
void osd_console_service(void);
void osd_console_show(void);          /* take over the screen, show the log */
void osd_console_hide(void);          /* return the screen to the Apple II */
void osd_console_hide_if_idle(uint32_t timeout_us); /* auto-dismiss boot console */

/* While locked out (the menu owns the screen), show() requests from other
 * threads are ignored and osd_log() only buffers — the menu is never stomped. */
void osd_console_set_lockout(bool lockout);

/* Copy up to max backlog lines (79 chars + NUL) for a remote viewer. */
int osd_console_snapshot(char dst[][OSD_CONSOLE_LINE_CAP], int max);

#endif
