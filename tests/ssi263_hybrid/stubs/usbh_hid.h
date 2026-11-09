#ifndef TEST_USBH_HID_H
#define TEST_USBH_HID_H
#include "usbh_core.h"
struct usbh_hid {
 struct usbh_hubport *hport;
 struct usb_endpoint_descriptor *intin, *intout;
 struct usbh_urb intin_urb,intout_urb;
 uint16_t report_size;
 uint8_t protocol,intf,minor;
 void *user_data;
};
int usbh_hid_set_protocol(struct usbh_hid *,uint8_t);
void usbh_hid_run(struct usbh_hid *);
void usbh_hid_stop(struct usbh_hid *);
#endif
