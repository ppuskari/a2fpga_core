// Host-only meter compatibility and integer dBFS approximation regression.
#include "mcu_hdmi_meter.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static void chk(int result,const char *description)
{
    if(!result){fprintf(stderr,"FAIL HDMI meter %s\n",description);exit(1);}
}
int main(void)
{
    uint8_t v1[HDMI_METER_BYTES]={'P','C',1,0,0,0,0,0,1};
    hdmi_meter_snapshot_t out;
    chk(!hdmi_meter_parse(v1,&out),"legacy PCM v1 misidentified as HM");
    uint8_t pkt[HDMI_METER_BYTES]={'H','M',1,0xA5,0xAC,0x65,0x39,0x30,0};
    chk(!hdmi_meter_parse(pkt,&out),"premature meter validity accepted");
    pkt[8]=1;
    chk(hdmi_meter_parse(pkt,&out),"HM v1 rejected");
    chk(out.clip_history==0xA5 && out.peak_l==26028 && out.peak_r==12345,
        "little-endian peak data or history");

    chk(hdmi_meter_attenuation_db10(0)==HDMI_METER_SILENT_DB10,
        "silence dB sentinel");
    chk(hdmi_meter_attenuation_db10(32768)==0,"full scale");
    chk(hdmi_meter_attenuation_db10(26028)==20,"-2.0 dBFS");
    chk(hdmi_meter_attenuation_db10(16384)==60,"-6.0 dBFS");
    chk(hdmi_meter_attenuation_db10(3277)==200,"-20.0 dBFS");

    for(unsigned p=1;p<=32768;p+=31u) {
        double actual=-20.0*log10((double)p/32768.0)*10.0;
        double estimated=(double)hdmi_meter_attenuation_db10((uint16_t)p);
        chk(fabs(estimated-actual)<1.1,"dBFS error exceeded 0.11 dB");
    }
    puts("PASS HDMI meter: optional old-FPGA fallback, snapshot, and integer dBFS within 0.11 dB");
    return 0;
}
