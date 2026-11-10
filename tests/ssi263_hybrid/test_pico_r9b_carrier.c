/* P10-R9B: isolate the Pico powered-idle carrier with the real C engine.
 * No FPGA, MCU, or Apple bus emulation implied. This is a controlled
 * zero-amplitude, powered-mode fixture. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "ssi263.h"

#define BLOCK 128
#define BLOCKS 220

static int measure(float carrier_db, unsigned *peak, unsigned long *nonzero, int *ar)
{
    ssi263_params p;
    ssi263_default_params(&p);
    p.xck_hz = 1020000.0f;
    p.carrier_rel_db = carrier_db;
    ssi263 *c = ssi263_new(&p, ssi263_default_rom(), 22050.0f);
    real y[BLOCK+1];
    short pcm[BLOCK+1];
    unsigned b, j;
    if (!c) return 1;
    /* Power on, choose an A/R-enabled phoneme mode, set amp=0, R4=$E8.
     * This deliberately tests carrier while the speech amplitude is zero. */
    ssi263_write(c, 3, 0x00);
    ssi263_write(c, 4, 0xE8);
    ssi263_write(c, 0, 0x40);
    *peak = 0;
    *nonzero = 0;
    for (b = 0; b < BLOCKS; ++b) {
        if (ssi263_run(c, BLOCK, y) != BLOCK) {
            ssi263_free(c);
            return 2;
        }
        ssi_pcm16(y, BLOCK, p.output_gain, pcm);
        if (b < 100) continue; /* ignore any initial startup settling */
        for (j=0; j < BLOCK; ++j) {
            int32_t v = pcm[j];
            unsigned mag = (unsigned)(v < 0 ? -v : v);
            if (mag > *peak) *peak = mag;
            if (mag) ++*nonzero;
        }
    }
    *ar = ssi263_request(c);
    ssi263_free(c);
    return 0;
}

int main(void)
{
    unsigned original_peak=0, quiet_peak=0;
    unsigned long original_nonzero=0, quiet_nonzero=0;
    int ar_original=0, ar_quiet=0;
    ssi263_params p;
    ssi263_default_params(&p);
    printf("R9B parameters: orig_carrier_dB=%.1f output_gain=%.2f\n",
           (double)p.carrier_rel_db, (double)p.output_gain);
    printf("R9B theoretical carrier for R4=E8: %.5f Hz\n",
           1020000.0 / (16.0 * (256 - 0xE8)));
    if (measure(p.carrier_rel_db, &original_peak, &original_nonzero, &ar_original)
        || measure(-200.0f, &quiet_peak, &quiet_nonzero, &ar_quiet))
        return 2;
    printf("R9B original peak=%u nonzero=%lu A/R=%d\n",
           original_peak, original_nonzero, ar_original);
    printf("R9B quiet peak=%u nonzero=%lu A/R=%d\n",
           quiet_peak, quiet_nonzero, ar_quiet);
    if (original_peak < 5 || original_peak > 64
        || quiet_peak > 1
        || original_nonzero == 0
        || quiet_nonzero > original_nonzero/100)
        return 1;
    puts("PASS: reference Pico's powered-idle carrier accounts for PCM16-scale output");
    return 0;
}
