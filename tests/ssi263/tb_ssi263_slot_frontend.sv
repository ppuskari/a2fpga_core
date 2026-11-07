// License: MIT
// Test the *bus contract*, NOT synthesized speech audio.
`timescale 1ns/1ps
module tb_ssi263_slot_frontend;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, enabled = 0, io_sel = 0, phi0 = 0, rw_n = 1;
    logic [7:0] addr = 0, data = 0;
    logic ar_n = 1, d7 = 1;
    wire selected, read_en, via_ca1, wr;
    wire [7:0] read_data, wr_data;
    wire [2:0] wr_reg;
    ssi263_slot_frontend dut(
        .clk_i(clk), .reset_n_i(rst_n),
        .enabled_i(enabled), .card_io_sel_i(io_sel),
        .phi0_i(phi0), .rw_n_i(rw_n),
        .card_addr_i(addr), .data_i(data),
        .ar_n_i(ar_n), .status_d7_i(d7),
        .speech_selected_o(selected), .speech_read_o(read_en),
        .speech_read_data_o(read_data), .via_ca1_o(via_ca1),
        .speech_write_o(wr), .speech_reg_o(wr_reg),
        .speech_data_o(wr_data)
    );

    initial begin
        repeat(3) @(negedge clk);
        rst_n = 1;
        enabled = 1;
        io_sel = 1;
        phi0 = 1;
        rw_n = 0;
        addr = 8'h43;
        data = 8'hB5;
        #1;
        if (!selected || read_en) $fatal(1,"$Cn43 must select SSI write");
        @(negedge clk);
        if (!wr || wr_reg !== 3'd3 || wr_data !== 8'hB5)
            $fatal(1,"Single write/reg/data capture failed");
        repeat(4) @(negedge clk);
        if (wr) $fatal(1,"Repeated SSI write while PHI0 remains asserted");

        phi0=0;
        io_sel=0;
        @(negedge clk);
        addr=8'h67; data=8'h28; phi0=1; io_sel=1;
        @(negedge clk);
        if (!wr || wr_reg !== 3'd7 || wr_data !== 8'h28)
            $fatal(1,"Aliased $Cn67 SSI register did not decode");

        phi0=0; io_sel=0; rw_n=1;
        @(negedge clk);
        phi0=1; io_sel=1; addr=8'h41;
        #1;
        if (!selected || !read_en || read_data !== 8'h80)
            $fatal(1,"D7 ready/status read missing");
        d7=0; ar_n=0;
        #1;
        if (read_data !== 8'h00 || via_ca1 !== 1'b0)
            $fatal(1,"Speech active-low A/R->VIA CA1 failed");
        d7=1; ar_n=1;

        // Do not capture the opposite VIA ($Cn80-$CnFF).
        addr=8'hC1; #1;
        if (selected || read_en) $fatal(1,"Incorrect right VIA overlap");
        addr=8'h21; #1;
        if (selected || read_en) $fatal(1,"Incorrect speech selection below $Cn40");
        io_sel=0; addr=8'h41; #1;
        if (selected) $fatal(1,"Selected outside active card IO window");
        enabled=0; io_sel=1; #1;
        if (selected || via_ca1 !== 1'b1)
            $fatal(1,"Disabled speech must preserve existing Mockingboard");
        $display("PASS: SSI263 bus selection, aliases, D7 read, A/R CA1, one-write-per-cycle, isolation");
        $finish;
    end

    initial begin
        #50000;
        $fatal(1,"SSI bus test timeout");
    end
endmodule
