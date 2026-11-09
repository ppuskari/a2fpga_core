#ifndef TEST_USB_OSAL_H
#define TEST_USB_OSAL_H
#define CONFIG_USBHOST_PSC_PRIO 28
void *usb_osal_thread_create(const char *name,int size,int priority,void (*fn)(void *),void *arg);
void usb_osal_thread_delete(void *arg);
#endif
