/*
 * P10-R3: BL616 CherryUSB HID *boot keyboard* input for the MCU menu.
 * Includes keyboard navigation alongside the existing XInput gamepad.
 * Not an Apple II keyboard emulator: only handles the MCU menu.
 *
 * HID IRQ completion never issues SPI or calls menu_input(). It queues
 * rising-edge actions, consumed from the existing 20ms xinput_thread.
 *
 * Confirmed API shape: CherryUSB 1.5.3 usbh_hid.h/demo/usb_host.c.
 */
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include "FreeRTOS.h"
#include "task.h"
#include "usb_osal.h"
#include "usbh_core.h"
#include "usbh_hid.h"
#include "usbh_xinput.h"
#include "osd_console.h"
#include "menu.h"
#include "usb_kbd_menu.h"

#define KBD_BUF_LEN 64
USB_NOCACHE_RAM_SECTION USB_MEM_ALIGNX static uint8_t s_report[KBD_BUF_LEN];
static struct usbh_hid *volatile s_keyboard;
static uint8_t s_previous[6];
static volatile uint16_t s_presses;
static volatile bool s_tab_pressed;

/* Standard USB HID boot keyboard usages (NOT ASCII). */
static uint16_t translate(uint8_t key)
{
    switch (key) {
        case 0x52: return XINPUT_DPAD_UP;
        case 0x51: return XINPUT_DPAD_DOWN;
        case 0x50: return XINPUT_DPAD_LEFT;
        case 0x4f: return XINPUT_DPAD_RIGHT;
        case 0x28: return XINPUT_A;   /* Enter */
        case 0x29: return XINPUT_B;   /* Escape */
        case 0x2a: return XINPUT_B;   /* Backspace */
        case 0x1c: return XINPUT_Y;   /* Y: console/menu */
        default: return 0;
    }
}

void usb_kbd_menu_process_boot_report(const uint8_t *r,int nbytes)
{
    if (!r || nbytes < 8) return;
    for (unsigned i=0; i<6; i++) {
        const uint8_t key=r[i+2];
        if (key==0 || key==1 || key==2 || key==3) continue;
        bool old=false;
        for (unsigned j=0;j<6;j++)
            if(s_previous[j]==key)old=true;
        if(old)continue;
        if(key==0x2b) s_tab_pressed=true;
        else s_presses |= translate(key);
    }
    memcpy(s_previous,r+2,sizeof(s_previous));
}

static void hid_in_cb(void *arg,int nbytes)
{
    struct usbh_hid *hid=(struct usbh_hid *)arg;
    if(hid!=s_keyboard) return; /* device detached */
    if(nbytes>0) {
        usb_kbd_menu_process_boot_report(s_report,nbytes);
        /* Copy descriptors are unchanged; rearm the same URB after callback.
         * No SPI, locks or FreeRTOS waits in HCD interrupt context. */
        usbh_submit_urb(&hid->intin_urb);
    } else if(nbytes == -USB_ERR_NAK) {
        usbh_submit_urb(&hid->intin_urb);
    }
}

static void kbd_start_thread(void *argument)
{
    struct usbh_hid *hid=(struct usbh_hid *)argument;
    if(hid!=s_keyboard || hid->intin==NULL) {
        usb_osal_thread_delete(NULL);
        return;
    }
    /* Force the standard 8-byte boot keyboard report; ignore keyboards that
     * cannot enter boot protocol rather than interpreting arbitrary report IDs. */
    int rc=usbh_hid_set_protocol(hid,0);
    if(rc<0) {
        osd_log("USB KBD: BOOT PROTOCOL UNSUPPORTED");
        usb_osal_thread_delete(NULL);
        return;
    }
    unsigned maxpacket=hid->intin->wMaxPacketSize;
    if(maxpacket<8 || maxpacket>KBD_BUF_LEN) {
        osd_log("USB KBD: BAD EP MPS=%u",maxpacket);
        usb_osal_thread_delete(NULL);
        return;
    }
    memset(s_report,0,sizeof(s_report));
    usbh_int_urb_fill(&hid->intin_urb,hid->hport,hid->intin,
                      s_report,maxpacket,0,hid_in_cb,hid);
    if(usbh_submit_urb(&hid->intin_urb)<0)
        osd_log("USB KBD: INTERRUPT IN FAILED");
    else
        osd_log("USB KBD: TAB OPENS MENU");
    usb_osal_thread_delete(NULL);
}

void usbh_hid_run(struct usbh_hid *hid)
{
    /* USB HID protocol: 1 keyboard, 2 mouse. Ignore all other HID devices. */
    if(!hid || hid->protocol!=1 || !hid->intin) return;
    if(s_keyboard) return; /* single keyboard in this first build */
    taskENTER_CRITICAL();
    s_keyboard=hid;
    memset(s_previous,0,sizeof(s_previous));
    s_presses=0;
    s_tab_pressed=false;
    taskEXIT_CRITICAL();
    usb_osal_thread_create("usb_kbd",2048,CONFIG_USBHOST_PSC_PRIO+1,
                           kbd_start_thread,hid);
}

void usbh_hid_stop(struct usbh_hid *hid)
{
    if(s_keyboard!=hid)return;
    taskENTER_CRITICAL();
    s_keyboard=NULL;
    memset(s_previous,0,sizeof(s_previous));
    s_presses=0;
    s_tab_pressed=false;
    taskEXIT_CRITICAL();
}

void usb_kbd_menu_poll(void)
{
    uint16_t presses;
    bool tab;
    taskENTER_CRITICAL();
    presses=s_presses;
    tab=s_tab_pressed;
    s_presses=0;
    s_tab_pressed=false;
    taskEXIT_CRITICAL();
    if(tab) menu_request_menu_view();
    if(presses) menu_inject(presses);
}
