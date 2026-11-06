// Validate the actual native YM2149 envelope source reused by MB-DOC.
// This timing test uses Verilator because the YM core has array reset patterns.
`timescale 1ns/1ps
module tb_ym2149_envelope;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic reset = 1'b1;
    logic bdir = 1'b0, bc = 1'b0;
    logic [7:0] di = 8'h00;
    wire [4:0] envelope;
    wire [7:0] data_o, ch_a, ch_b, ch_c, ioa, iob;
    wire [5:0] active;

    YM2149 dut (
        .CLK(clk), .CE(1'b1), .RESET(reset),
        .BDIR(bdir), .BC(bc), .DI(di), .DO(data_o),
        .CHANNEL_A(ch_a), .CHANNEL_B(ch_b), .CHANNEL_C(ch_c),
        .ENV_LEVEL(envelope), .SEL(1'b0), .MODE(1'b0),
        .ACTIVE(active), .IOA_in(8'h00), .IOA_out(ioa),
        .IOB_in(8'h00), .IOB_out(iob)
    );

    task automatic wr(input logic [7:0] a, input logic [7:0] d);
        @(negedge clk); bdir=1'b1; bc=1'b1; di=a;
        @(negedge clk); bdir=1'b1; bc=1'b0; di=d;
        @(negedge clk); bdir=1'b0; bc=1'b0;
    endtask

    initial begin
        repeat (5) @(negedge clk);
        reset=1'b0;
        wr(8'd11,8'd1); // low byte, period=1
        wr(8'd12,8'd0); // high byte
        wr(8'd13,8'h09); // descending ramp then hold at zero
        repeat (3) @(negedge clk);
        if (envelope !== 5'd31)
            $fatal(1, "shape 9 did not restart at full amplitude: %d",envelope);
        repeat (300) @(negedge clk);
        if (envelope !== 5'd0)
            $fatal(1, "shape 9 did not decay and hold at zero: %d",envelope);
        repeat (80) @(negedge clk);
        if (envelope !== 5'd0)
            $fatal(1, "shape 9 did not remain zero");

        // Writing identical shape code again must retrigger, not be coalesced.
        wr(8'd13,8'h09);
        repeat (3) @(negedge clk);
        if (envelope !== 5'd31)
            $fatal(1, "repeated register-13 write failed to retrigger");

        wr(8'd13,8'h0D); // ascending ramp and hold
        repeat (3) @(negedge clk);
        if (envelope !== 5'd0)
            $fatal(1, "shape D attack did not restart at zero");
        repeat (300) @(negedge clk);
        if (envelope !== 5'd31)
            $fatal(1, "shape D did not rise and hold: %d",envelope);

        // PSG RESET from VIA PB2 must restore initial envelope state.
        @(negedge clk); reset=1'b1;
        repeat(3) @(negedge clk);
        if (envelope !== 5'd31)
            $fatal(1, "PSG RESET did not restore initial envelope");
        $display("PASS: native YM2149 envelope periods, shapes 9/D, repeated register-13 retrigger and RESET");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Timeout in native YM2149 envelope test");
    end
endmodule
