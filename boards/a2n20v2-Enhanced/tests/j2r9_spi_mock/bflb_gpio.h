#ifndef J2R9_GPIO_MOCK_H
#define J2R9_GPIO_MOCK_H
#include <stdint.h>
struct bflb_device_s { int dummy; };
#define GPIO_PIN_0 0
#define GPIO_PIN_1 1
#define GPIO_PIN_2 2
#define GPIO_PIN_3 3
#define GPIO_OUTPUT 0x01
#define GPIO_PULLUP 0x02
#define GPIO_SMT_EN 0x04
#define GPIO_DRV_3 0x08
#define GPIO_FUNC_SPI0 0x10
#define GPIO_ALTERNATE 0x20
struct bflb_device_s *bflb_device_get_by_name(const char *name);
void bflb_gpio_init(struct bflb_device_s *dev, uint32_t pin, uint32_t mode);
void bflb_gpio_set(struct bflb_device_s *dev, uint32_t pin);
void bflb_gpio_reset(struct bflb_device_s *dev, uint32_t pin);
#endif
