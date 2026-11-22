#ifndef J2R9_SPI_MOCK_H
#define J2R9_SPI_MOCK_H
#include <stdint.h>
#include "bflb_gpio.h"
#define SPI_ROLE_MASTER 1
#define SPI_MODE1 1
#define SPI_DATA_WIDTH_8BIT 8
#define SPI_BIT_MSB 1
#define SPI_BYTE_LSB 0
struct bflb_spi_config_s {
    uint32_t freq;
    uint32_t role, mode, data_width, bit_order, byte_order;
    uint32_t tx_fifo_threshold, rx_fifo_threshold;
};
void bflb_spi_init(struct bflb_device_s *dev, const struct bflb_spi_config_s *cfg);
int bflb_spi_poll_exchange(struct bflb_device_s *dev, const uint8_t *tx,
                           uint8_t *rx, uint32_t length);
#endif
