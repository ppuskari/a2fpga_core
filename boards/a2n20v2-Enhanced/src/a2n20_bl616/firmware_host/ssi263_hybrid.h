#ifndef SSI263_HYBRID_H
#define SSI263_HYBRID_H

/* P10 real-time BL616 speech renderer; source model from pinned Pico C.
 * FPGA independently preserves SSI CPU register timing and VIA CA1/A-R.
 * Entry point launches the FreeRTOS audio task from main().
 */
void ssi263_hybrid_task(void *arg);
#endif
