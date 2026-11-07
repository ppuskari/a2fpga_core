// SSI-263 Apple II Mockingboard speech socket: register bus front-end.
// Original A2FPGA development code, based on the published SSI-263A bus
// interface and documented Mockingboard C $Cn40-$Cn7F speech address range.
// No HDL from Appletini One is copied into this file.
//
// **Not a speech synthesizer.** Interface contract for a future audio engine.
// KEEP OUT of production .fs until an actual SSI-263 core has been connected.
module ssi263_slot_frontend (
    input  logic       clk_i,
    input  logic       reset_n_i,
    input  logic       enabled_i,
    input  logic       card_io_sel_i,
    input  logic       phi0_i,
    input  logic       rw_n_i,
    input  logic [7:0] card_addr_i,
    input  logic [7:0] data_i,

    // Speech engine owns the A/R active-low output and status D7 bit.
    input  logic       ar_n_i,
    input  logic       status_d7_i,

    // To Apple bus and left VIA CA1.
    output logic       speech_selected_o,
    output logic       speech_read_o,
    output logic [7:0] speech_read_data_o,
    output logic       via_ca1_o,

    // To SSI-263 engine, one strobe per Apple bus *write cycle*.
    output logic       speech_write_o,
    output logic [2:0] speech_reg_o,
    output logic [7:0] speech_data_o
);
    // SSI-263AP on Mockingboard C maps A6 high, A7 low.
    // A5/A4/A3 are aliases; A2:A0 select the speech register.
    logic speech_address_w;
    logic write_selected_w;
    logic prev_write_selected_r;

    assign speech_address_w =
        enabled_i && card_io_sel_i &&
        card_addr_i[7:6] == 2'b01;
    assign speech_selected_o = speech_address_w;
    assign speech_read_o = speech_address_w && rw_n_i;
    // Only D7 has a defined SSI-263 software-visible status.
    // Other bits are left low; consumers must mask bit 7.
    assign speech_read_data_o = {status_d7_i, 7'b0};
    assign via_ca1_o = enabled_i ? ar_n_i : 1'b1;
    assign write_selected_w = speech_address_w && !rw_n_i && phi0_i;

    always_ff @(posedge clk_i) begin
        if (!reset_n_i || !enabled_i) begin
            speech_write_o <= 1'b0;
            speech_reg_o <= 3'b0;
            speech_data_o <= 8'b0;
            prev_write_selected_r <= 1'b0;
        end else begin
            speech_write_o <= write_selected_w && !prev_write_selected_r;
            prev_write_selected_r <= write_selected_w;
            if (write_selected_w && !prev_write_selected_r) begin
                speech_reg_o <= card_addr_i[2:0];
                speech_data_o <= data_i;
            end
        end
    end
endmodule
