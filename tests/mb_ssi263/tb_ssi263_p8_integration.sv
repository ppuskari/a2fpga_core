// Byte-for-byte beginning of Mockingboard Demo Disk 1's speech engine.
// Disk file "COMPOSITE DRIVER" at $6D00 initializes SSI R0=$C0,
// R3=$70, enables RIGHT VIA CA1 IRQ via STA $C48E/#$82.
// It then streams five-byte records backwards from "MESS", each ordered
// [R4,R3,R2,R1,R0], by STA $C440,X with X=4..0.
// This test models the actual peripheral transactions and approximate
// 1.02 MHz XCK. No Apple II 6502/6522 binary is executed in simulation.
`timescale 1ns/1ps
module tb_ssi263_p8_integration;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n=0, en=1, sel=0, xck=0, rw_n=1, data_strobe=0;
    logic [7:0] addr=0, data=0;
    wire selected, read_enable, ar_n, powered;
    wire [7:0] read_data;
    wire [5:0] phoneme;
    wire signed [15:0] pcm;
    logic ever_spoke=0;

    // Select complete independent chip, bypass legacy control/renderer.
    ssi263_slot #(.FULL_CHIP_ENABLE(1'b1)) dut (
        .clk_i(clk), .reset_n_i(reset_n), .enabled_i(en),
        .card_io_sel_i(sel), .xck_tick_i(xck), .data_in_strobe_i(data_strobe), .rw_n_i(rw_n),
        .card_addr_i(addr), .data_i(data),
        .speech_selected_o(selected), .speech_read_o(read_enable),
        .speech_data_o(read_data), .via_ca1_o(ar_n),
        .powered_o(powered), .phoneme_o(phoneme),
        .speech_pcm_o(pcm)
    );
    always @(posedge clk)
        if (reset_n && pcm !== 16'sd0) ever_spoke <= 1'b1;

    task automatic cpu_wr(input logic [7:0] r, input logic [7:0] v);
        @(negedge clk);
        // Model real Apple bridge: selection and R/W appear ahead of data;
        // an old read byte ($A5) remains until data_in_strobe.
        addr = r; data = 8'hA5; rw_n=0; sel=1;
        repeat(3) @(negedge clk);
        data = v; data_strobe=1;
        @(negedge clk); data_strobe=0;
        repeat(2) @(negedge clk);
        sel=0; rw_n=1;
        repeat(3) @(negedge clk);
    endtask
    task automatic ticks(input integer n);
        for(integer i=0;i<n;i++) begin
            @(negedge clk); xck=1;
            @(negedge clk); xck=0;
        end
    endtask
    task automatic disk_record(input logic [39:0] rec);
        begin
            cpu_wr(8'h44,rec[39:32]);
            cpu_wr(8'h43,rec[31:24]);
            cpu_wr(8'h42,rec[23:16]);
            cpu_wr(8'h41,rec[15:8]);
            cpu_wr(8'h40,rec[7:0]);
        end
    endtask

    initial begin
        repeat(8) @(negedge clk);
        reset_n=1;
        cpu_wr(8'h43,8'h80); // $6D40: standby
        cpu_wr(8'h40,8'hC0); // $6D45: duration/mode=3, pause
        cpu_wr(8'h43,8'h70); // $6D4A: power up and mode latch
        // Verify P2 read-only diagnostics without affecting the original
        // SSI control behavior; real reads are sampled with rw_n asserted.
        @(negedge clk); sel=1; rw_n=1; addr=8'h43;
        #1;
        if (!read_enable || read_data !== 8'hA5)
            $fatal(1,"P2 signature read mux missing");
        addr=8'h41;
        #1;
        if (read_data !== 8'd3)
            $fatal(1,"P2 write counter missed an SSI write: %0d",read_data);
        addr=8'h44;
        #1;
        if (read_data !== 8'd1)
            $fatal(1,"P2 powered diagnostic missing");
        addr=8'h42;
        #1;
        if (read_data !== 8'd0)
            $fatal(1,"P2 XCK count should start at zero");
        addr=8'h45;
        #1;
        if (read_data !== 8'd3)
            $fatal(1,"P3 last SSI register address is not R3");
        addr=8'h46;
        #1;
        if (read_data !== 8'h70)
            $fatal(1,"P3 last SSI data was not $70");
        addr=8'h47;
        #1;
        if (read_data !== 8'h70)
            $fatal(1,"P3 internal R3 did not latch $70");
        addr=8'h48;
        #1;
        if (read_data !== 8'd1)
            $fatal(1,"P3 power-up transition counter missing");
        sel=0;
        if (!powered || ar_n!==1'b1 || pcm!==16'sd0)
            $fatal(1,"SSI startup pause/standby sequence wrong");

        // The initial all-zero phoneme is silent. One SSI timer period
        // must request the FIRST MESS record via the VIA's CA1 edge.
        ticks(65535);
        @(negedge clk); sel=1; rw_n=1; addr=8'h42;
        #1;
        if (read_data !== 8'hFF)
            $fatal(1,"P2 XCK diagnostic should saturate at 255");
        sel=0;
        if (ar_n!==1'b1) $fatal(1,"First SSI IRQ arrived too early");
        ticks(1);
        if (ar_n!==1'b0 || read_data[7]!==1'b1)
            $fatal(1,"SSI failed to request first MESS phoneme");

        // MESS at $5002: L, followed by A, then YI.
        disk_record(40'hE87FA86F60); // L (R0=$60 -> code $20)
        if (!powered || phoneme!==6'h20 || ar_n!==1'b1)
            $fatal(1,"First disk phoneme L not accepted");
        // RATE=$A8 => frame=4096*(16-10)=24576 cycles;
        // R0 $60 duration=1 -> 3 frames => 73728 XCKs.
        ticks(73727);
        if (ar_n!==1'b1 || !ever_spoke)
            $fatal(1,"First L vowel PCM or duration missing");
        ticks(1);
        if (ar_n!==1'b0)
            $fatal(1,"L phoneme did not fire its CA1 IRQ");

        disk_record(40'hE86EA86388); // second original record: A
        if (phoneme!==6'h08 || ar_n!==1'b1)
            $fatal(1,"Second disk record failed to clear request");
        if (pcm===16'sd0)
            $display("NOTE: PCM can be between nonzero samples when testing");
        disk_record(40'hE85DA85B44); // third original record: YI
        if (phoneme!==6'h04 || ar_n!==1'b1)
            $fatal(1,"Third MESS record not accepted");
        cpu_wr(8'h43,8'h80);
        repeat(3) @(negedge clk);
        if (powered || pcm !== 16'sd0)
            $fatal(1,"Demo stop did not mute speech");

        $display("PASS: Disk 1 SSI demo initial IRQ, MESS L/A/YI, CA1 timing, PCM and stop");
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1,"Mockingboard speech demo sequence simulation timeout");
    end
endmodule
