#ifndef SSI263_SPI_BENCH_H
#define SSI263_SPI_BENCH_H
#include <stdint.h>
typedef struct {
    uint32_t bytes_per_direction;
    uint32_t write_bytes_per_sec;
    uint32_t read_bytes_per_sec;
    uint32_t total_bytes_per_sec;
    uint32_t mismatches;
    uint32_t write_elapsed_us;
    uint32_t read_elapsed_us;
} ssi263_spi_bench_result;
ssi263_spi_bench_result ssi263_spi_bench_run(void);
#endif
