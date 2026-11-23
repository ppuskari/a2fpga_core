// M3 HDMI post-mixer diagnostics: optional SPACE6 read-only extension.
// Does not alter HxCMOD, PCM FIFO or SD-burst behavior.
#ifndef MCU_HDMI_METER_H
#define MCU_HDMI_METER_H
#include <stdbool.h>
#include <stdint.h>
#define HDMI_METER_ADDR 0x800010u
#define HDMI_METER_BYTES 9u
typedef struct {
    uint8_t clip_history;
    uint16_t peak_l, peak_r; // Unsigned abs(sample), 0..32768
} hdmi_meter_snapshot_t;
// Return false if FPGA does not support the extension or 1s data not ready.
bool hdmi_meter_parse(const uint8_t packet[HDMI_METER_BYTES],
                      hdmi_meter_snapshot_t *out);
// Return attenuation in positive tenths dBFS: 20 denotes -2.0 dBFS.
// Silent input returns HDMI_METER_SILENT_DB10, not a finite dB level.
#define HDMI_METER_SILENT_DB10 0xFFFFu
unsigned hdmi_meter_attenuation_db10(uint16_t unsigned_peak);
#endif
