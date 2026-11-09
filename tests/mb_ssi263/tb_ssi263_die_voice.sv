`timescale 1ns/1ps
// P7 die-param renderer isolated regression. Run from Enhanced board folder
// so the same $readmemh relative path as Gowin is exercised.
module tb_ssi263_die_voice;
    logic clk=0;
    always #5 clk=~clk;
    logic rst_n=0, powered=0, start=0;
    logic [5:0] phoneme=6'd1;
    logic [3:0] amplitude=4'd15;
    logic [7:0] inflection=8'd80, rate=8'h20;
    wire signed [15:0] pcm;
    integer nonzero=0;
    integer transitions=0;
    logic signed [15:0] prior=0;

    ssi263_die_formant_voice #(
        .CLK_HZ(64000),
        .SAMPLE_HZ(16000)
    ) dut (
        .clk_i(clk), .reset_n_i(rst_n), .powered_i(powered),
        .phoneme_start_i(start), .phoneme_i(phoneme),
        .amplitude_i(amplitude), .inflection_i(inflection),
        .rate_i(rate), .pcm_o(pcm)
    );

    always @(negedge clk) begin
        if (rst_n && powered) begin
            if (^pcm === 1'bx) $fatal(1,"P7 PCM contains unknown bits");
            if (pcm != 0) nonzero=nonzero+1;
            if (pcm != prior) transitions=transitions+1;
        end
        prior=pcm;
    end

    initial begin
        repeat(5) @(negedge clk);
        rst_n=1;
        repeat(3) @(negedge clk);
        powered=1; start=1;
        @(negedge clk); start=0;
        repeat(2000) @(negedge clk);
        if (nonzero < 100 || transitions < 100)
            $fatal(1,"Die-formant renderer silent or stalled: nonzero=%0d transitions=%0d",nonzero,transitions);
        // Speech renderer is not the bus/timer owner; silence on poweroff
        // must not leave a residual sample.
        powered=0;
        repeat(2) @(negedge clk);
        if (pcm !== 16'sd0) $fatal(1,"P7 did not mute on poweroff");
        $display("PASS: die-param renderer activity and poweroff, nonzero=%0d transitions=%0d",nonzero,transitions);
        $finish;
    end
    initial begin #200000; $fatal(1,"P7 voice timeout"); end
endmodule
