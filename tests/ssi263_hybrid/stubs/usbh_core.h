#ifndef TEST_USBH_CORE_H
#define TEST_USBH_CORE_H
#include <stdint.h>
#define USB_NOCACHE_RAM_SECTION
#define USB_MEM_ALIGNX __attribute__((aligned(4)))
#define USB_ERR_NAK 11
struct usbh_hubport { int dummy; };
struct usb_endpoint_descriptor { uint16_t wMaxPacketSize; };
struct usbh_urb { unsigned allocated; };
void usbh_int_urb_fill(struct usbh_urb *,struct usbh_hubport *,struct usb_endpoint_descriptor *,void *,int,int,void (*)(void *,int),void *);
int usbh_submit_urb(struct usbh_urb *);
#endif
