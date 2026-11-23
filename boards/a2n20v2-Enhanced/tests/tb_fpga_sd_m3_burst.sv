// M3 hardware RTL regression: real fpga_sd_spi byte engine plus
// autonomous 512-byte burst receiver. No BL616 driver or SD PHY stub
// substitutes for the actual bit-clock master.
`timescale 1ns/1ps
module tb_fpga_sd_m3_burst;
    reg clk=0,rst_n=0,cs_n=1,slow=0;
    always #9 clk=~clk;  // 54MHz-class FPGA system clock
    reg start=0,abort=0,legacy_start=0;
    reg [7:0] legacy_tx=8'hA5;
    wire burst_tx_start,burst_active,complete,error;
    wire [7:0] burst_tx_data;
    wire sd_busy,sd_clk,sd_mosi,sd_cs_n,sd_miso;
    wire [7:0] sd_rx;
    reg rd_req=0;
    reg [8:0] rd_addr=0;
    wire rd_valid;
    wire [7:0] rd_data;
    integer sd_bits=0,starts=0,wait_cycles=0;
    integer i;
    reg [7:0] expect_byte;

    function [7:0] pattern(input integer n);
        pattern=(n*37+11)^((n>>3)*7);
    endfunction
    // SD card drives its next bit before the rising edge where the
    // fpga_sd_spi samples it, with unique nontrivial data for every byte.
    assign sd_miso = pattern(sd_bits/8)[7 - (sd_bits%8)];
    always @(posedge sd_clk) begin
        if (!sd_cs_n) sd_bits <= sd_bits+1;
    end
    always @(posedge clk) begin
        if (burst_tx_start) begin
            starts <= starts+1;
            if (burst_tx_data !== 8'hFF)
                $fatal(1,"autonomous SD MOSI must send FF");
        end
    end

    fpga_sd_spi dut_spi(
        .clk(clk),.rst_n(rst_n),.cs_n_i(cs_n),.slow_clk_i(slow),
        .tx_start_i(burst_tx_start | legacy_start),
        .tx_data_i(burst_active?burst_tx_data:legacy_tx),
        .rx_data_o(sd_rx),.busy_o(sd_busy),
        .sd_clk_o(sd_clk),.sd_mosi_o(sd_mosi),
        .sd_miso_i(sd_miso),.sd_cs_n_o(sd_cs_n)
    );
    fpga_sd_burst dut_burst(
        .clk(clk),.rst_n(rst_n),.start_i(start),.abort_i(abort),
        .cs_n_i(cs_n),.sd_busy_i(sd_busy),.sd_rx_data_i(sd_rx),
        .sd_tx_start_o(burst_tx_start),.sd_tx_data_o(burst_tx_data),
        .active_o(burst_active),.complete_o(complete),.error_o(error),
        .rd_req_i(rd_req),.rd_addr_i(rd_addr),
        .rd_valid_o(rd_valid),.rd_data_o(rd_data)
    );
    initial begin
        repeat (6) @(negedge clk);
        rst_n=1;
        cs_n=0;
        @(negedge clk);start=1;
        @(negedge clk);start=0;

        wait_cycles=0;
        while (!complete && wait_cycles<60000) begin
            @(negedge clk);
            wait_cycles=wait_cycles+1;
        end
        if (!complete || error || burst_active)
            $fatal(1,"burst did not finish: cycles=%0d err=%0d",wait_cycles,error);
        if (starts!==512 || sd_bits!==4096)
            $fatal(1,"bad burst byte count starts=%0d bits=%0d",starts,sd_bits);

        for (i=0;i<512;i=i+1) begin
            @(negedge clk);rd_addr=i;rd_req=1;
            @(negedge clk);
            if (!rd_valid) $fatal(1,"read port did not assert VALID");
            expect_byte=pattern(i);
            if (rd_data !== expect_byte)
                $fatal(1,"mismatch byte %0d got %02x exp %02x",
                       i,rd_data,expect_byte);
            rd_req=0;
        end
        // The next ordinary register-initiated SD byte must still work.
        @(negedge clk);legacy_start=1;
        @(negedge clk);legacy_start=0;
        wait(sd_busy);
        wait(!sd_busy);
        if (sd_bits!==4104)
            $fatal(1,"legacy byte failed after burst (%0d bits)",sd_bits);

        // A START with CS# high must fail harmlessly, no SD clocking.
        @(negedge clk);cs_n=1;start=1;
        @(negedge clk);start=0;
        repeat(3) @(negedge clk);
        if (!complete || !error || burst_active)
            $fatal(1,"CS-high burst must raise fault");
        @(negedge clk);abort=1;
        @(negedge clk);abort=0;
        repeat(2) @(negedge clk);
        if (complete || error)
            $fatal(1,"ABORT must reset result status");
        $display("PASS M3 SD RTL 512B: 4096 SD clocks, exact 512B buffer, legacy byte, CS abort");
        $finish;
    end
endmodule
