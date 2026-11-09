#ifndef A2N20_USB_KBD_MENU_H
#define A2N20_USB_KBD_MENU_H
#include <stdint.h>

/* Called once per 20ms menu tick from xinput_thread, NOT USB interrupt.
 * USB HID callback only queues key-down edges; all FPGA SPI remains in
 * the regular menu task. TAB opens the menu, ESC returns, arrows navigate. */
void usb_kbd_menu_poll(void);

/* Pure boot-keyboard report decoder, also used by host-side tests. */
void usb_kbd_menu_process_boot_report(const uint8_t *report, int len);
#endif
