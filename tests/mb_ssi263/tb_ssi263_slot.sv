// SSI-263 isolated Mockingboard C bus/timer regression.
// Icarus: iverilog -g2012 -s tb_ssi263_slot -o /tmp/mb_ssi.vvp
//    hdl/mockingboard/ssi263_control.sv
//    hdl/mockingboard/ssi263_slot.sv tests/mb_ssi263/tb_ssi263_slot.sv
// vvp /tmp/mb_ssi.vvp
`timescale 1ns/1ps
module tb_ssi263_slot;
    reg clk=0;
    always #5 clk=~clk;
    reg reset_n=0, en=1, sel=0, tick=0, rw_n=1, data_strobe=0;
    reg [7:0] addr=0, data=0;
    wire speech_sel, speech_rd, ca1_n, powered;
    wire [7:0] speech_data;
    wire [5:0] phoneme;
    wire signed [15:0] speech_pcm;
    logic nonzero_pcm = 1'b0;
    always @(posedge clk) if (reset_n && speech_pcm != 16'sd0) nonzero_pcm <= 1'b1;

    ssi263_slot dut (
        .clk_i(clk), .reset_n_i(reset_n), .enabled_i(en),
        .card_io_sel_i(sel), .xck_tick_i(tick),
        .data_in_strobe_i(data_strobe),
        .rw_n_i(rw_n), .card_addr_i(addr), .data_i(data),
        .speech_selected_o(speech_sel), .speech_read_o(speech_rd),
        .speech_data_o(speech_data), .via_ca1_o(ca1_n),
        .powered_o(powered), .phoneme_o(phoneme),
        .speech_pcm_o(speech_pcm)
    );

    task automatic write_reg(input [7:0] addr_in, input [7:0] value);
        begin
            @(negedge clk);
            sel=1; rw_n=0; addr=addr_in; data=8'hA5;
            repeat(3) @(negedge clk); // early address phase has stale data
            data=value; data_strobe=1;
            @(negedge clk); data_strobe=0;
            repeat(2) @(negedge clk);
            sel=0; rw_n=1;
            repeat(4) @(negedge clk);
        end
    endtask

    task automatic xcks(input integer cycles);
        integer i;
        begin
            for(i=0;i<cycles;i=i+1) begin
                @(negedge clk); tick=1;
                @(negedge clk); tick=0;
            end
        end
    endtask

    initial begin
        repeat(5) @(negedge clk);
        reset_n=1;
        @(negedge clk);
        if (powered !== 1'b0 || ca1_n !== 1'b1)
            $fatal(1,"SSI must reset powerdown with CA1 inactive");
        sel=1; addr=8'h20; rw_n=1;
        #1;
        if (speech_sel !== 1'b0 || speech_rd !== 1'b0)
            $fatal(1,"$Cn20 incorrectly decoded as C socket");
        addr=8'h80; #1;
        if (speech_sel !== 1'b0)
            $fatal(1,"$Cn80 must remain right VIA");
        addr=8'h40; #1;
        if (!speech_sel || !speech_rd || speech_data !== 8'h00)
            $fatal(1,"$Cn40 status idle decode failed");
        sel=0; @(negedge clk);

        // Mode 2, 2 frames, rate 15: 2*4096 XCK cycles.
        write_reg(8'h42,8'hF0); // R2 rate15
        write_reg(8'h40,8'h86); // R0 phoneme6, duration bits10
        write_reg(8'h43,8'h0F); // CTL 1->0, amplitude15
        if (!powered || phoneme !== 6'd6)
            $fatal(1,"CTL enable or R0 storage failure");
        if (ca1_n !== 1'b1)
            $fatal(1,"A/R must remain inactive during phoneme");

        // Avoid the testbench's final-negedge/posedge race exactly at
        // the 8192-XCK boundary. Assert an 8-cycle timing aperture while
        // still rejecting materially early or late requests.
        xcks(8188);
        if (!nonzero_pcm) $fatal(1,"FPGA speech audio never became nonzero");
        if (ca1_n !== 1'b1)
            $fatal(1,"Premature A/R request (>4 XCK before expiration)");
        xcks(8);
        if (ca1_n !== 1'b0)
            $fatal(1,"Expected falling-edge CA1 near 8192 XCKs");

        sel=1; addr=8'h47; rw_n=1; #1;
        if (!speech_rd || speech_data !== 8'h0F)
            $fatal(1,"P3 SSI R3 diagnostic readback failed");
        addr=8'h40; #1;
        if (speech_data !== 8'h80)
            $fatal(1,"SSI A/R D7 status missing at primary register");
        sel=0; @(negedge clk);

        // Writing R0 acknowledges request, starts a fresh phoneme.
        write_reg(8'h40,8'h81);
        if (ca1_n !== 1'b1 || phoneme !== 6'd1)
            $fatal(1,"R0 retrigger failed to clear A/R");

        // Another control write with D7=1 powers down immediately.
        write_reg(8'h43,8'h80);
        if (powered || !ca1_n)
            $fatal(1,"CTL powerdown failed");
        repeat(4) @(negedge clk);
        if (speech_pcm !== 16'sd0) $fatal(1,"Speech PCM survived powerdown");

        // Mode 0 has no A/R interrupt even after its timer expires.
        write_reg(8'h40,8'h00);
        write_reg(8'h43,8'h0F);
        xcks(16384);
        if (!ca1_n)
            $fatal(1,"Mode0 produced an A/R pulse");

        en=0;
        repeat(3) @(negedge clk);
        if (ca1_n !== 1'b1 || powered)
            $fatal(1,"Disabling card did not isolate SSI/CA1");
        $display("PASS: SSI263 $Cn40 decode, D7, 8192-XCK CA1, nonzero phoneme PCM, powerdown");
        $finish;
    end

    initial begin
        #10000000;
        $fatal(1,"SSI-263 slot test timeout");
    end
endmodule
