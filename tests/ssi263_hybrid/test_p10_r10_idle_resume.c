/* R10: exact-zero idle admission, write-before-wake and restart tests.
 * Builds against the real Pico SSI model with the digital carrier excluded.
 * Host timing/phase tests do NOT qualify the BL616 or FPGA hardware path. */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "ssi263.h"
#include "ssi263_digital_idle.h"

#define N 128
#define RATE 22050
#define IDLE_BLOCKS 650
#define WAKE_BLOCKS 48

static void require(int ok, const char *msg)
{
    if (!ok) { fprintf(stderr,"FAIL: %s\n",msg); exit(1); }
}

static void unit_check(void)
{
    ssi263_digital_idle s;
    short zeros[N]={0};
    short almost[N]={0};
    ssi263_digital_idle_init(&s,RATE,2500u);
    require(s.needed_zeros==55125u,"2.5s equals 55125 PCM samples");
    for (unsigned i=0;i<1000;i++)
        ssi263_digital_idle_observe(&s,zeros,N,false);
    require(!s.skipping,"A/R alone or zero with no A/R must not skip");
    almost[7]=1;
    for (unsigned i=0;i<500;i++)
        ssi263_digital_idle_observe(&s,almost,N,true);
    require(!s.skipping,"near-zero nonzero PCM must not skip");
    for (unsigned i=0;i<430;i++)
        ssi263_digital_idle_observe(&s,zeros,N,true);
    require(!s.skipping,"must not skip before full guard");
    ssi263_digital_idle_observe(&s,zeros,N,true);
    require(s.skipping && s.consecutive_zeros==55125u,"guard reaches exact threshold");
    require(ssi263_digital_idle_can_skip(&s,true),"A/R asserted permits skip");
    ssi263_digital_idle_skipped(&s);
    require(s.skipped_blocks==1u,"skip accounting");
    ssi263_digital_idle_write(&s);
    require(!s.skipping && s.consecutive_zeros==0u && s.wakes==1u,
            "incoming SSI write must wake before phoneme");
    require(!ssi263_digital_idle_can_skip(&s,false),"deasserted A/R forbids skip");
    ssi263_digital_idle_write(&s);
    require(s.wakes==1u,"non-sleeping writes are not counted as wakes");
}

static ssi263 *new_model(ssi263_params *p)
{
    ssi263_default_params(p);
    p->xck_hz=1020000.0f;
    ssi263 *c=ssi263_new(p,ssi263_default_rom(),(real)RATE);
    require(c!=NULL,"model allocation");
    /* R0 high bits determine phoneme mode latched at first CTL power-on. */
    ssi263_write(c,4,0xe8);
    ssi263_write(c,2,0xa8);
    ssi263_write(c,1,0x6f);
    ssi263_write(c,0,0xe0);
    ssi263_write(c,3,0x70); /* powered, MODE3, zero amplitude */
    ssi263_write(c,0,0xe0);
    return c;
}

int main(void)
{
    unit_check();
    ssi263_params pa,pb;
    ssi263 *a=new_model(&pa),*b=new_model(&pb);
    ssi263_digital_idle idle;
    ssi263_digital_idle_init(&idle,RATE,2500u);
    real ya[N+1],yb[N+1];
    short va[N+1],vb[N+1];
    unsigned long baseline_idle_nonzero=0,skipped_pcm_nonzero=0;
    unsigned long awake_nonzero_a=0,awake_nonzero_b=0;
    unsigned first_active_a=WAKE_BLOCKS,first_active_b=WAKE_BLOCKS;
    double energy_a=0.0,energy_b=0.0;
    for(unsigned blk=0;blk<IDLE_BLOCKS;blk++) {
        require(ssi263_run(a,N,ya)==N,"baseline idle render");
        ssi_pcm16(ya,N,pa.output_gain,va);
        for(unsigned j=0;j<N;j++)if(va[j])++baseline_idle_nonzero;
        if(ssi263_digital_idle_can_skip(&idle,ssi263_request(b)!=0)) {
            ssi263_skip(b,(real)N/(real)RATE);
            memset(vb,0,sizeof(vb));
            ssi263_digital_idle_skipped(&idle);
        } else {
            require(ssi263_run(b,N,yb)==N,"candidate idle render");
            ssi_pcm16(yb,N,pb.output_gain,vb);
            ssi263_digital_idle_observe(&idle,vb,N,ssi263_request(b)!=0);
        }
        for(unsigned j=0;j<N;j++)if(vb[j])++skipped_pcm_nonzero;
    }
    printf("R10 idle baseline_nonzero=%lu skip_nonzero=%lu skips=%lu ar=%d\n",
           baseline_idle_nonzero,skipped_pcm_nonzero,
           (unsigned long)idle.skipped_blocks,ssi263_request(b));
    require(baseline_idle_nonzero==0 && skipped_pcm_nonzero==0,
            "permanent no-carrier model emits exact PCM16 zeros at powered idle");
    require(idle.skipped_blocks>25 && idle.skipping,
            "model enters idle skip only after sustained exact digital zero");
    unsigned prior_wakes=idle.wakes;
    /* A new Apple command must wake before it is applied to the model. */
    ssi263_digital_idle_write(&idle);
    require(!idle.skipping && idle.wakes==prior_wakes+1,"first write wakes model");
    ssi263_write(a,3,0x7f);
    ssi263_write(b,3,0x7f);
    ssi263_write(a,0,0xe0);
    ssi263_write(b,0,0xe0);
    for(unsigned blk=0;blk<WAKE_BLOCKS;blk++) {
        require(ssi263_run(a,N,ya)==N,"baseline wake render");
        require(ssi263_run(b,N,yb)==N,"candidate wake render");
        ssi_pcm16(ya,N,pa.output_gain,va);
        ssi_pcm16(yb,N,pb.output_gain,vb);
        ssi263_digital_idle_observe(&idle,vb,N,ssi263_request(b)!=0);
        unsigned nz_a=0,nz_b=0;
        for(unsigned j=0;j<N;j++) {
            int32_t x=va[j],y=vb[j];
            if(x) { ++awake_nonzero_a; ++nz_a; }
            if(y) { ++awake_nonzero_b; ++nz_b; }
            energy_a+=(double)x*x;
            energy_b+=(double)y*y;
        }
        if(nz_a && first_active_a==WAKE_BLOCKS)first_active_a=blk;
        if(nz_b && first_active_b==WAKE_BLOCKS)first_active_b=blk;
    }
    printf("R10 wake first baseline=%u skipped=%u blocks; nonzero baseline=%lu skipped=%lu; energy ratio=%.4f; wakes=%lu\n",
           first_active_a,first_active_b,awake_nonzero_a,awake_nonzero_b,
           energy_a>0.0?energy_b/energy_a:0.0,(unsigned long)idle.wakes);
    require(awake_nonzero_a>0 && awake_nonzero_b>0,"speech resumes in both paths");
    require(first_active_a<WAKE_BLOCKS && first_active_b<=first_active_a+2,
            "idle sleep must not delay first speech more than two 128-sample blocks");
    require(energy_b>energy_a*0.20 && energy_b<energy_a*5.0,
            "wake speech energy remains of comparable order");
    require(!idle.skipping,"synth should remain awake during active voiced output");
    ssi263_free(a);
    ssi263_free(b);
    puts("PASS: exact zero + A/R admission, real Pico skip, and wake on next SSI write");
    return 0;
}
