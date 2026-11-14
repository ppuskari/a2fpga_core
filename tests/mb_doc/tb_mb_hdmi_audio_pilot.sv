`timescale 1ns/1ps
module tb_mb_hdmi_audio_pilot;
    logic clk=0, reset_n=0, sample_tick=0;
    always #5 clk=~clk;
    logic signed [15:0] left_in=0, right_in=0;
    wire signed [15:0] on_l,on_r,off_l,off_r;
    mb_hdmi_audio_pilot #(.ENABLE(1'b1)) enabled (
        .clk_pixel_i(clk),.reset_n_i(reset_n),.sample_tick_i(sample_tick),
        .left_pcm_i(left_in),.right_pcm_i(right_in),
        .left_pcm_o(on_l),.right_pcm_o(on_r)
    );
    mb_hdmi_audio_pilot #(.ENABLE(1'b0)) disabled (
        .clk_pixel_i(clk),.reset_n_i(reset_n),.sample_tick_i(sample_tick),
        .left_pcm_i(left_in),.right_pcm_i(right_in),
        .left_pcm_o(off_l),.right_pcm_o(off_r)
    );

    initial begin : run
        integer i;
        repeat (3) @(negedge clk);
        reset_n=1;
        // Confirm an independent +/-256 square pilot during total music
        // silence. The rate is 44.1kHz / (2*22) = 1002.27 Hz.
        for(i=0;i<132;i++)begin
            @(negedge clk);
            sample_tick=1;
            #1;
            if(on_l!==16'sd0 ||
               on_r!==((i/22)%2 ? 16'sd256 : -16'sd256))
                $fatal(1,"Pilot sample %0d got L=%0d R=%0d",i,on_l,on_r);
            if(off_l!==0 || off_r!==0)
                $fatal(1,"Disabled pilot changed silence");
            @(negedge clk);
            sample_tick=0;
        end

        // On the right only: music mixed with pilot, left untouched.
        left_in=16'sd1000;right_in=16'sd1000;
        #1;
        if(on_l!==16'sd1000 || on_r!==16'sd744 ||
           off_l!==16'sd1000 || off_r!==16'sd1000)
            $fatal(1,"Pilot mixed wrong channels: %0d %0d",on_l,on_r);

        // Post-limiter must never exceed the M6 -2dBFS ceiling.
        right_in=-16'sd26000;
        #1;
        if(on_r!==-16'sd26028)
            $fatal(1,"Negative music ceiling not preserved: %0d",on_r);
        // Advance exactly half a pilot cycle to positive polarity.
        repeat(22) begin
            @(negedge clk);sample_tick=1;
            @(negedge clk);sample_tick=0;
        end
        right_in=16'sd26000;
        #1;
        if(on_r!==16'sd26028)
            $fatal(1,"Positive music ceiling not preserved: %0d",on_r);
        if(off_r!==16'sd26000)
            $fatal(1,"Disabled source was modified");

        // Pixel clock without audio tick must never advance pilot phase.
        repeat(100) @(negedge clk);
        if(on_r!==16'sd26028)
            $fatal(1,"Pilot advanced without sample tick");
        $display("PASS: 1002.27 Hz right-only postgain HDMI diagnostic pilot");
        $display("PASS: independent of DOC zeros; ceiling +/-26028; disabled transparent");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1,"Timeout in pilot RTL test");
    end
endmodule
