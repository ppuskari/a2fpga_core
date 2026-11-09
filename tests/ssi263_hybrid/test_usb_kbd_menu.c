#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "usbh_hid.h"
#include "usbh_xinput.h"
#include "usb_kbd_menu.h"

static int menu_requested, reports_started, logs;
static uint16_t buttons;
void menu_request_menu_view(void){menu_requested++;}
void menu_inject(uint16_t b){buttons|=b;}
void osd_log(const char *fmt,...) {(void)fmt;logs++;}
void *usb_osal_thread_create(const char *n,int sz,int pri,void(*fn)(void*),void *arg) {
  (void)n;(void)sz;(void)pri;fn(arg);return (void *)1;
}
void usb_osal_thread_delete(void *arg){(void)arg;}
int usbh_hid_set_protocol(struct usbh_hid *hid,uint8_t p){
  (void)hid;assert(p==0);return 0;
}
void usbh_int_urb_fill(struct usbh_urb *u,struct usbh_hubport *h,
                      struct usb_endpoint_descriptor *ep,void *b,int len,
                      int tm,void (*cb)(void*,int),void *arg) {
 (void)h;(void)ep;(void)b;(void)len;(void)tm;(void)cb;(void)arg;u->allocated=1;
}
int usbh_submit_urb(struct usbh_urb *u){assert(u->allocated);reports_started++;return 0;}
int main(void) {
  struct usb_endpoint_descriptor ep={.wMaxPacketSize=8};
  struct usbh_hubport port={0};
  struct usbh_hid mouse={.hport=&port,.intin=&ep,.protocol=2};
  struct usbh_hid kbd={.hport=&port,.intin=&ep,.protocol=1};
  uint8_t r[8]={0};
  usbh_hid_run(&mouse);assert(reports_started==0);
  usbh_hid_run(&kbd);assert(reports_started==1);
  r[2]=0x2b; /* TAB */
  usb_kbd_menu_process_boot_report(r,8);
  usb_kbd_menu_poll();
  assert(menu_requested==1&&buttons==0);
  /* Holding TAB produces no second menu event. */
  usb_kbd_menu_process_boot_report(r,8);
  usb_kbd_menu_poll(); assert(menu_requested==1);
  memset(r,0,sizeof(r));
  usb_kbd_menu_process_boot_report(r,8);usb_kbd_menu_poll();
  r[2]=0x52; /* up */
  r[3]=0x28; /* enter */
  usb_kbd_menu_process_boot_report(r,8);usb_kbd_menu_poll();
  assert((buttons&(XINPUT_DPAD_UP|XINPUT_A))==(XINPUT_DPAD_UP|XINPUT_A));
  buttons=0;
  r[2]=0x29; /* escape */
  r[3]=0x1c; /* Y */
  usb_kbd_menu_process_boot_report(r,8);usb_kbd_menu_poll();
  assert((buttons&(XINPUT_B|XINPUT_Y))==(XINPUT_B|XINPUT_Y));
  usbh_hid_stop(&kbd);
  buttons=0;
  usb_kbd_menu_poll();assert(buttons==0);
  puts("PASS P10-R3: HID keyboard TAB edges, arrows, Enter, Escape, Y, and unplug cleanup");
  return 0;
}
