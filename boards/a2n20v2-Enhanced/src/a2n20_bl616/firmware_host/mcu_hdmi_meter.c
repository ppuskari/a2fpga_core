#include "mcu_hdmi_meter.h"
#include <stddef.h>

bool hdmi_meter_parse(const uint8_t packet[HDMI_METER_BYTES],
                      hdmi_meter_snapshot_t *out)
{
    if (!packet || !out || packet[0] != 'H' || packet[1] != 'M' ||
        packet[2] != 1u || (packet[8] & 1u) == 0u)
        return false;
    out->clip_history = packet[3];
    out->peak_l = (uint16_t)packet[4] | ((uint16_t)packet[5] << 8);
    out->peak_r = (uint16_t)packet[6] | ((uint16_t)packet[7] << 8);
    return true;
}

/* Pure integer log2() in Q8: 8 fractional bits from repeated squaring.
 * No FPU, libm, table, heap allocation or audio-thread processing.
 * Called only when emitting the ~9-second OSD telemetry batch.
 * 20log10(x) == 6.0205999 * log2(x).
 */
unsigned hdmi_meter_attenuation_db10(uint16_t peak)
{
    if (!peak)
        return HDMI_METER_SILENT_DB10;
    if (peak >= 32768u)
        return 0u;
    unsigned integer_log2 = 0u;
    for (uint32_t p = peak; (p >>= 1u) != 0u;)
        integer_log2++;
    uint32_t normalized_q16 = ((uint32_t)peak << (16u - integer_log2));
    unsigned fraction_q8 = 0u;
    for (int bit = 7; bit >= 0; bit--) {
        normalized_q16 =
            (uint32_t)(((uint64_t)normalized_q16 * normalized_q16) >> 16);
        if (normalized_q16 >= (2u << 16)) {
            normalized_q16 >>= 1;
            fraction_q8 |= (1u << (unsigned)bit);
        }
    }
    const unsigned attenuation_log2_q8 =
        ((15u - integer_log2) << 8) - fraction_q8;
    // 6.0206 dB/octave = 60.206 tenths/octave.
    return (attenuation_log2_q8 * 60206u + 128000u) / 256000u;
}
