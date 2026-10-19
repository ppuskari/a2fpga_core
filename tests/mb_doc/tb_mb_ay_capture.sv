// Standalone unit tests for the two MB AY write-capture paths.
// Compile with hdl/mockingboard/mockingboard.sv and the normal project's
// interface dependencies using a SystemVerilog-capable simulator.
//
// This test bench tests the mb_ay_capture module, not VIA/slot decoding.
// Full mixed Verilog/VHDL A2FPGA and real-hardware tests remain required.
`timescale 1ns/1ps
module tb_mb_ay_capture;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic reset_n = 1'b0;
    logic enable = 1'b0;
    logic [7:0] left_data = 8'h00;
    logic [7:0] right_data = 8'h00;
    logic left_bdir = 1'b0, left_bc = 1'b0;
    logic right_bdir = 1'b0, right_bc = 1'b0;
    logic left_wr, right_wr;
    logic [3:0] left_reg, right_reg;
    logic [7:0] left_value, right_value;

    mb_ay_capture left (
        .clk_i(clk), .reset_n_i(reset_n), .enable_i(enable),
        .bdir_i(left_bdir), .bc_i(left_bc), .data_i(left_data),
        .wr_o(left_wr), .reg_o(left_reg), .value_o(left_value)
    );

    mb_ay_capture right (
        .clk_i(clk), .reset_n_i(reset_n), .enable_i(enable),
        .bdir_i(right_bdir), .bc_i(right_bc), .data_i(right_data),
        .wr_o(right_wr), .reg_o(right_reg), .value_o(right_value)
    );

    task automatic step(
        input logic [1:0] left_ctrl,
        input logic [7:0] left_byte,
        input logic [1:0] right_ctrl,
        input logic [7:0] right_byte
    );
        @(negedge clk);
        left_bdir = left_ctrl[1];
        left_bc = left_ctrl[0];
        left_data = left_byte;
        right_bdir = right_ctrl[1];
        right_bc = right_ctrl[0];
        right_data = right_byte;
        @(posedge clk);
        #1;
    endtask

    task automatic check_none();
        if (left_wr !== 1'b0 || right_wr !== 1'b0)
            $fatal(1, "Unexpected AY write L=%b R=%b", left_wr, right_wr);
    endtask

    task automatic check_left(
        input logic [3:0] reg_exp,
        input logic [7:0] data_exp
    );
        if (left_wr !== 1'b1 || right_wr !== 1'b0 ||
            left_reg !== reg_exp || left_value !== data_exp)
            $fatal(1, "Left AY mismatch wr=%b reg=%h data=%h",
                   left_wr, left_reg, left_value);
    endtask

    task automatic check_right(
        input logic [3:0] reg_exp,
        input logic [7:0] data_exp
    );
        if (right_wr !== 1'b1 || left_wr !== 1'b0 ||
            right_reg !== reg_exp || right_value !== data_exp)
            $fatal(1, "Right AY mismatch wr=%b reg=%h data=%h",
                   right_wr, right_reg, right_value);
    endtask

    initial begin
        // Reset and disabled card cannot report events.
        step(2'b00, 8'h00, 2'b00, 8'h00);
        check_none();
        reset_n = 1'b1;
        enable = 1'b1;
        step(2'b00, 8'h00, 2'b00, 8'h00);
        check_none();

        // Left AY: latch register 13 (envelope shape), then hold
        // a data-write bus phase for multiple 54 MHz clock cycles.
        step(2'b11, 8'h0D, 2'b00, 8'h00);
        check_none();
        step(2'b00, 8'h0D, 2'b00, 8'h00);
        step(2'b10, 8'hA5, 2'b00, 8'h00);
        check_none();
        step(2'b10, 8'hA5, 2'b00, 8'h00);
        check_none();
        step(2'b10, 8'hA5, 2'b00, 8'h00);
        check_none();
        step(2'b00, 8'h00, 2'b00, 8'h00);
        check_left(4'hD, 8'hA5);
        step(2'b00, 8'h00, 2'b00, 8'h00);
        check_none();

        // Deliberate repeated *identical* register-13 write.
        // This is a new envelope trigger even if value is same.
        step(2'b10, 8'hA5, 2'b00, 8'h00);
        step(2'b00, 8'h00, 2'b00, 8'h00);
        check_left(4'hD, 8'hA5);

        // Right AY and left AY are independently addressed.
        step(2'b00, 8'h00, 2'b11, 8'h07);
        step(2'b00, 8'h00, 2'b10, 8'h3F);
        check_none();
        step(2'b00, 8'h00, 2'b00, 8'h00);
        check_right(4'h7, 8'h3F);

        // Invalid high-nibble AY address must be ignored.
        step(2'b11, 8'h90, 2'b00, 8'h00);
        step(2'b10, 8'h55, 2'b00, 8'h00);
        step(2'b00, 8'h00, 2'b00, 8'h00);
        check_none();

        // While disabled, reset pending address/write state.
        enable = 1'b0;
        step(2'b11, 8'h00, 2'b00, 8'h00);
        step(2'b10, 8'hFE, 2'b00, 8'h00);
        step(2'b00, 8'h00, 2'b00, 8'h00);
        check_none();
        enable = 1'b1;
        step(2'b10, 8'hFE, 2'b00, 8'h00);
        step(2'b00, 8'h00, 2'b00, 8'h00);
        check_none();

        // Address validity recovers after disabled/reset period.
        step(2'b11, 8'h00, 2'b00, 8'h00);
        step(2'b10, 8'h12, 2'b00, 8'h00);
        step(2'b00, 8'h00, 2'b00, 8'h00);
        check_left(4'h0, 8'h12);

        $display("PASS: MB dual AY capture, held BDIR, reset and reg13");
        $finish;
    end
endmodule
