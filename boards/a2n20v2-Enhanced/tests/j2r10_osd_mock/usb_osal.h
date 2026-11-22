#ifndef J2R10_OSAL_MOCK_H
#define J2R10_OSAL_MOCK_H
typedef void *usb_osal_mutex_t;
usb_osal_mutex_t usb_osal_mutex_create(void);
void usb_osal_mutex_take(usb_osal_mutex_t mutex);
void usb_osal_mutex_give(usb_osal_mutex_t mutex);
#endif
