/* R7: pure C regression for transient smoothing, no toolchain dependency. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "ssi263_audio_edges.h"
static int aabs(int x) {return x<0?-x:x;}
int main(void)
{
    ssi263_audio_edges s;
    ssi263_audio_edges_init(&s,22050u,18u,2500u,16u);
    assert(s.quiet_samples>=397u);
    assert(s.attack_samples==56u);
    assert(s.armed==1u);
    int16_t x=ssi263_audio_edges_sample(&s,30000);
    assert(x>0 && x<800);
    for(unsigned i=1;i<s.attack_samples;i++)
        x=ssi263_audio_edges_sample(&s,30000);
    assert(x==30000 && s.attacks==1u);
    assert(ssi263_audio_edges_sample(&s,30000)==30000);
    /* A 10ms stop consonant gap is too short to re-arm the shaper. */
    for(unsigned i=0;i<220;i++)
        (void)ssi263_audio_edges_sample(&s,0);
    assert(ssi263_audio_edges_sample(&s,12000)==12000);
    assert(s.attacks==1u);
    /* 20ms true digital quiet followed by a fresh word onset -> 2.5ms ramp. */
    for(unsigned i=0;i<450;i++)
        (void)ssi263_audio_edges_sample(&s,0);
    assert(s.armed==1u);
    assert(ssi263_audio_edges_sample(&s,12000)<500);
    assert(s.attacks==2u);
    for(unsigned i=1;i<s.attack_samples;i++)
        (void)ssi263_audio_edges_sample(&s,12000);
    assert(ssi263_audio_edges_sample(&s,-32768)==-32768);
    /* Edge fades disabled for unbiased A/B testing. */
    ssi263_audio_edges_init(&s,11025u,18u,0u,16u);
    assert(ssi263_audio_edges_sample(&s,-32768)==-32768);
    /* Re-arm on SSI powerdown, but don't touch the register machine. */
    ssi263_audio_edges_init(&s,44100u,18u,2500u,16u);
    (void)ssi263_audio_edges_sample(&s,32000);
    ssi263_audio_edges_rearm(&s);
    assert(aabs(ssi263_audio_edges_sample(&s,32000))<500);
    puts("PASS R7 PCM attack 44k/22k/11k, intentional short gaps, full-scale, disable and restart");
    return 0;
}
