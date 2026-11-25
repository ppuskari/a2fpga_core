#ifndef J2R10_SCREEN_MOCK_H
#define J2R10_SCREEN_MOCK_H
#define FPGA_SCREEN_WIDE_W 80u
void fpga_screen_set_columns(unsigned columns);
void fpga_screen_clear(void);
void fpga_screen_home(void);
void fpga_screen_puts(const char *s);
#endif
