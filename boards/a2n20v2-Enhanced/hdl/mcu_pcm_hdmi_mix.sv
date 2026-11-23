// M3 experiment: unity-level BL616 MOD playback to final HDMI mixer.
// The existing native/DOC/AY/SSI chain is already gain-calibrated.
// MOD PCM is independently limited to -2 dBFS by mcu_mod_gain.c.
//
// Preserve native samples bit-for-bit when the MOD PCM stream is zero.
// During overlap, add MOD at unity and bound the *final* sample peak to
// +/-26028 (-2.0 dBFS). This is a hard safety ceiling, NOT a lookahead
// compressor: frequent over-peak events can distort and must be measured.
// Report those events to the existing HDMI clip-history diagnostic.
module mcu_pcm_hdmi_mix #(
    parameter integer PEAK_CEILING = 26028
) (
    input  wire signed [15:0] native_l_i,
    input  wire signed [15:0] native_r_i,
    input  wire signed [15:0] mod_l_i,
    input  wire signed [15:0] mod_r_i,
    output wire signed [15:0] mix_l_o,
    output wire signed [15:0] mix_r_o,
    output wire               over_peak_o
);
    wire mod_present_w = (mod_l_i != 16'sd0) || (mod_r_i != 16'sd0);

    wire signed [17:0] sum_l_w =
        $signed({{2{native_l_i[15]}}, native_l_i}) +
        $signed({{2{mod_l_i[15]}}, mod_l_i});
    wire signed [17:0] sum_r_w =
        $signed({{2{native_r_i[15]}}, native_r_i}) +
        $signed({{2{mod_r_i[15]}}, mod_r_i});

    function automatic signed [15:0] limit_peak;
        input signed [17:0] sample;
        begin
            if (sample > PEAK_CEILING)
                limit_peak = 16'(PEAK_CEILING);
            else if (sample < -PEAK_CEILING)
                limit_peak = 16'(-PEAK_CEILING);
            else
                limit_peak = sample[15:0];
        end
    endfunction

    assign mix_l_o = mod_present_w ? limit_peak(sum_l_w) : native_l_i;
    assign mix_r_o = mod_present_w ? limit_peak(sum_r_w) : native_r_i;
    assign over_peak_o = mod_present_w &&
        ((sum_l_w > PEAK_CEILING) || (sum_l_w < -PEAK_CEILING) ||
         (sum_r_w > PEAK_CEILING) || (sum_r_w < -PEAK_CEILING));
endmodule
