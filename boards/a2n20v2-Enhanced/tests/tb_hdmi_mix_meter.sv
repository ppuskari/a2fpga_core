// Fast clock-domain crossing test: SAMPLE_RATE=4 makes one "second"
// four audio sample ticks; the full production build uses 44100.
`timescale 1ns/1ps
module tb_hdmi_mix_meter;
    reg pixel_clk=0,logic_clk=0,reset_n=0,tick=0;
    reg signed [15:0] sample_l=0,sample_r=0;
    reg [7:0] history=0;
    wire [15:0] peak_l,peak_r;
    wire [7:0] clip;
    wire valid;
    always #5 pixel_clk=~pixel_clk;
    always #3 logic_clk=~logic_clk;

    hdmi_mix_meter #(.SAMPLE_RATE(4)) dut(
        .clk_pixel_i(pixel_clk),.clk_logic_i(logic_clk),
        .reset_n_i(reset_n),.sample_tick_i(tick),
        .sample_l_i(sample_l),.sample_r_i(sample_r),
        .clip_history_i(history),
        .peak_l_o(peak_l),.peak_r_o(peak_r),
        .clip_history_o(clip),.valid_o(valid)
    );
    task automatic sample(input signed [15:0] l,
                          input signed [15:0] r,
                          input [7:0] h);
    begin
        @(negedge pixel_clk); sample_l=l;sample_r=r;history=h;tick=1;
        @(negedge pixel_clk); tick=0;
    end endtask
    initial begin
        repeat(4) @(negedge pixel_clk);reset_n=1;
        sample(16'sd1000,-16'sd10000,8'h01);
        sample(16'sd26028,16'sd7000,8'h0f);
        sample(-16'sd1234,-16'sh8000,8'h3f);
        if(valid!==0)begin
            $display("FAIL HDMI meter published partial window");$fatal(1);
        end
        sample(-16'sd5,16'sd25,8'hA5);
        repeat(8) @(negedge logic_clk);
        if(valid!==1 || peak_l!==16'd26028 ||
           peak_r!==16'd32768 || clip!==8'hA5) begin
            $display("FAIL HDMI snapshot valid=%b left=%d right=%d clip=%02x",
                      valid,peak_l,peak_r,clip);
            $fatal(1);
        end
        // New window must not overwrite until four more audio ticks.
        sample(16'sd2,16'sd3,8'h00);
        sample(16'sd12000,16'sd300,8'h00);
        repeat(8) @(negedge logic_clk);
        if(peak_l!==16'd26028 || peak_r!==16'd32768)begin
            $display("FAIL HDMI meter changed mid-window");$fatal(1);
        end
        sample(-16'sd50,16'sd400,8'h00);
        sample(16'sd25,16'sd1,8'h00);
        repeat(8) @(negedge logic_clk);
        if(peak_l!==16'd12000 || peak_r!==16'd400 || clip!==8'h00)begin
            $display("FAIL HDMI second snapshot L=%d R=%d CLIP=%02x",
                     peak_l,peak_r,clip);$fatal(1);
        end
        $display("PASS HDMI meter: 1s stereo sample peaks, abs(-32768), stable bundled CDC and clip history");
        $finish;
    end
    initial begin #100000;$display("FAIL HDMI meter timeout");$fatal(1);end
endmodule
