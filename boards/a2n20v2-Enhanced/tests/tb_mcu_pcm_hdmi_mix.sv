// M3 experiment: final HDMI mixing headroom regression.
// Run: iverilog -g2012 -s tb_mcu_pcm_hdmi_mix -o pcm_mix.vvp
//      boards/a2n20v2-Enhanced/hdl/mcu_pcm_hdmi_mix.sv
//      boards/a2n20v2-Enhanced/tests/tb_mcu_pcm_hdmi_mix.sv
//      && vvp pcm_mix.vvp
`timescale 1ns/1ps
module tb_mcu_pcm_hdmi_mix;
    logic signed [15:0] native_l, native_r, mod_l, mod_r;
    wire signed [15:0] output_l, output_r;
    wire clipped;
    mcu_pcm_hdmi_mix dut (
        .native_l_i(native_l), .native_r_i(native_r),
        .mod_l_i(mod_l), .mod_r_i(mod_r),
        .mix_l_o(output_l), .mix_r_o(output_r),
        .over_peak_o(clipped)
    );

    task automatic check(
        input integer nl, input integer nr,
        input integer ml, input integer mr,
        input integer expected_l, input integer expected_r,
        input bit expected_clip
    );
        begin
            native_l = 16'(nl);
            native_r = 16'(nr);
            mod_l = 16'(ml);
            mod_r = 16'(mr);
            #1;
            if (output_l !== 16'(expected_l) ||
                output_r !== 16'(expected_r) ||
                clipped !== expected_clip) begin
                $display("FAIL native=%0d/%0d MOD=%0d/%0d output=%0d/%0d clip=%b expected=%0d/%0d clip=%b",
                         nl,nr,ml,mr,output_l,output_r,clipped,
                         expected_l,expected_r,expected_clip);
                $fatal(1);
            end
        end
    endtask

    initial begin
        // No MOD samples: leave the original native-only HDMI path identical,
        // including non-Mockingboard modes that may reach beyond -2 dBFS.
        check(32000,-32000,0,0,32000,-32000,0);
        check(0,0,0,0,0,0,0);

        // MOD alone: full unity, not the old -6.02 dB final attenuation.
        check(0,0,26028,-26028,26028,-26028,0);
        check(0,0,10000,-10000,10000,-10000,0);

        // Stereo-linked peak guard: both channels limited independently,
        // with a combined event flag when either exceeds the ceiling.
        check(13014,-13014,13014,-13014,26028,-26028,0);
        check(25000,-25000,10000,-10000,26028,-26028,1);
        check(-26000,26000,26000,-26000,0,0,0);
        check(0,20000,10000,10000,10000,26028,1);
        check(0,0,-32768,32767,-26028,26028,1);

        // A nonzero MOD frame triggers the final bus guard on both sides.
        check(32000,10000,0,1,26028,10001,1);
        $display("PASS M3 HDMI: MOD unity, stereo, -2 dBFS overlap ceiling, silent-MOD native bypass");
        $finish;
    end
endmodule
