#ifndef TEST_FPGA_SPI_H
#define TEST_FPGA_SPI_H
#include <stdint.h>
#define FPGA_SPACE_LOCAL 0
void fpga_spi_xfer_write(uint8_t space,uint32_t addr,const uint8_t*src,uint16_t len);
void fpga_spi_xfer_read(uint8_t space,uint32_t addr,uint8_t*dst,uint16_t len);
#endif
