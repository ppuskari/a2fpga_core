//
// Mockingboard clone for the Apple II
// Model A: two AY-3-8913 chips for six audio channels
//
// Based on Alex Steremberg's Verilog port:
// https://github.com/alanswx/Apple-II-Verilog_MiSTer/blob/master/rtl/mockingboard/mockingboard.v
// of original W. Soltys <wsoltys@gmail.com> version:
// https://github.com/MiSTer-devel/Apple-II_MiSTer/blob/master/rtl/mockingboard/mockingboard.vhd
//
// Adapted for use with A2FPGA multicard bus interface
//
// Using the Gideon Zweijtzer 6522 VIA core and the MikeJ/Sorgelig YM2149 core
//
// Tested with the Thomas Skibo 6522 VIA core as well as other YM2149 cores such
// as the Matthew Hagerty YM2149 core.  The combination used here appears to have
// the best compatibility with the Mockingboard.
//

module Mockingboard #(
    parameter bit [7:0] ID = 2,
    parameter bit ENABLE = 1'b1
) (
    a2bus_if.slave a2bus_if,
    slot_if.card slot_if,

    output [7:0] data_o,
    output rd_en_o,
    output irq_n_o,

    output [9:0] audio_l_o,
    output [9:0] audio_r_o,

    // Decoded AY writes for the exclusive MB-to-DOC bridge.
    // One pulse per completed AY data-write phase; left/right
    // chips have independent event outputs.
    output logic       ay_l_wr_o,
    output logic [3:0] ay_l_reg_o,
    output logic [7:0] ay_l_data_o,
    output logic       ay_r_wr_o,
    output logic [3:0] ay_r_reg_o,
    output logic [7:0] ay_r_data_o
);

    reg card_enable;

    always @(posedge a2bus_if.clk_logic) begin
        if (!a2bus_if.system_reset_n) begin
            card_enable <= 1'b0;
        end else if (!slot_if.config_select_n) begin
            if (slot_if.slot == 3'd0) begin  // disable all cards when slot 0 is selected for configuration
                card_enable <= 1'b0;
            end else if (slot_if.card_id == ID) begin // enable this card
                card_enable <= slot_if.card_enable && ENABLE;
            end
        end
    end

    wire card_sel = card_enable && (slot_if.card_id == ID) && a2bus_if.phi0;
    wire card_dev_sel = card_sel && !slot_if.dev_select_n;
    wire card_io_sel = card_sel && !slot_if.io_select_n;

    wire [7:0] pb_l_o;
    wire [7:0] pb_r_o;

    wire [7:0] psg_r_i;
    wire [7:0] psg_r_o;
    wire [7:0] psg_l_i;
    wire [7:0] psg_l_o;

    wire [7:0] psg_al_o;
    wire [7:0] psg_bl_o;
    wire [7:0] psg_cl_o;
    wire [9:0] psg_ol_o;

    wire [7:0] psg_ar_o;
    wire [7:0] psg_br_o;
    wire [7:0] psg_cr_o;
    wire [9:0] psg_or_o;

    wire [7:0] data_l_o;
    wire [7:0] data_r_o;

    wire irq_l_o;
    wire irq_r_o;

    assign rd_en_o = card_io_sel & a2bus_if.rw_n;

    assign data_o  = (a2bus_if.addr[7] == 1'b0) ? data_l_o : data_r_o;

    // Contrary to some schematics, Mockingboards and Phasors only use IRQ, not NMI
    // Possibly some some versions of the Mockingboard used NMI, but inspected boards
    // do not have the NMI line connected.
    assign irq_n_o = (~(irq_l_o | irq_r_o)) | (~card_enable);

    // Left Channel

    via6522 m6522_left (
        .clock  (a2bus_if.clk_logic),
        .rising (a2bus_if.phi1_negedge),
        .falling(a2bus_if.phi1_posedge),
        .reset  (~a2bus_if.system_reset_n),

        .addr(a2bus_if.addr[3:0]),
        .wen(!a2bus_if.rw_n & !a2bus_if.addr[7] & card_io_sel & card_enable),
        .ren(a2bus_if.rw_n & !a2bus_if.addr[7] & card_io_sel & card_enable),
        .data_in(a2bus_if.data),
        .data_out(data_l_o),

        .phi2_ref(),

        .port_a_o(psg_l_i),
        .port_a_t(),
        .port_a_i(psg_l_o),

        .port_b_o(pb_l_o),
        .port_b_t(),
        .port_b_i(8'hFF),

        .ca1_i(1'b1),
        .ca2_o(),
        .ca2_i(1'b0),
        .ca2_t(),

        .cb1_o(),
        .cb1_i(1'b0),
        .cb1_t(),

        .cb2_o(),
        .cb2_i(1'b0),
        .cb2_t(),

        .irq(irq_l_o)
    );


    YM2149 psg_left (
        .CLK(a2bus_if.clk_logic),
        .CE(a2bus_if.phi1_negedge & card_enable),
        .RESET(~pb_l_o[2]),
        .BDIR(pb_l_o[1]),
        .BC(pb_l_o[0]),
        .DI(psg_l_i),
        .DO(psg_l_o),
        .CHANNEL_A(psg_al_o),
        .CHANNEL_B(psg_bl_o),
        .CHANNEL_C(psg_cl_o),

        .SEL (1'b0),
        .MODE(1'b0),

        .ACTIVE(),

        .IOA_in (8'b0),
        .IOA_out(),

        .IOB_in (8'b0),
        .IOB_out()
    );

    // maximum value is 10 bits (255 + 255 + 255)
    assign audio_l_o = psg_al_o + psg_bl_o + psg_cl_o;

    mb_ay_capture ay_capture_left (
        .clk_i(a2bus_if.clk_logic),
        .reset_n_i(a2bus_if.system_reset_n & pb_l_o[2]),
        .enable_i(card_enable),
        .bdir_i(pb_l_o[1]),
        .bc_i(pb_l_o[0]),
        .data_i(psg_l_i),
        .wr_o(ay_l_wr_o),
        .reg_o(ay_l_reg_o),
        .value_o(ay_l_data_o)
    );

    // Right Channel

    via6522 m6522_right (
        .clock  (a2bus_if.clk_logic),
        .rising (a2bus_if.phi1_negedge),
        .falling(a2bus_if.phi1_posedge),
        .reset  (~a2bus_if.system_reset_n),

        .addr(a2bus_if.addr[3:0]),
        .wen(!a2bus_if.rw_n & a2bus_if.addr[7] & card_io_sel & card_enable),
        .ren(a2bus_if.rw_n & a2bus_if.addr[7] & card_io_sel & card_enable),
        .data_in(a2bus_if.data),
        .data_out(data_r_o),

        .phi2_ref(),

        .port_a_o(psg_r_i),
        .port_a_t(),
        .port_a_i(psg_r_o),

        .port_b_o(pb_r_o),
        .port_b_t(),
        .port_b_i(8'hFF),

        .ca1_i(1'b1),
        .ca2_o(),
        .ca2_i(1'b0),
        .ca2_t(),

        .cb1_o(),
        .cb1_i(1'b0),
        .cb1_t(),

        .cb2_o(),
        .cb2_i(1'b0),
        .cb2_t(),

        .irq(irq_r_o)
    );


    YM2149 psg_right (
        .CLK(a2bus_if.clk_logic),
        .CE(a2bus_if.phi1_negedge & card_enable),
        .RESET(~pb_r_o[2]),
        .BDIR(pb_r_o[1]),
        .BC(pb_r_o[0]),
        .DI(psg_r_i),
        .DO(psg_r_o),
        .CHANNEL_A(psg_ar_o),
        .CHANNEL_B(psg_br_o),
        .CHANNEL_C(psg_cr_o),

        .SEL (1'b0),
        .MODE(1'b0),

        .ACTIVE(),

        .IOA_in (8'b0),
        .IOA_out(),

        .IOB_in (8'b0),
        .IOB_out()
    );

    assign audio_r_o = psg_ar_o + psg_br_o + psg_cr_o;

    mb_ay_capture ay_capture_right (
        .clk_i(a2bus_if.clk_logic),
        .reset_n_i(a2bus_if.system_reset_n & pb_r_o[2]),
        .enable_i(card_enable),
        .bdir_i(pb_r_o[1]),
        .bc_i(pb_r_o[0]),
        .data_i(psg_r_i),
        .wr_o(ay_r_wr_o),
        .reg_o(ay_r_reg_o),
        .value_o(ay_r_data_o)
    );

endmodule

// Capture the logical AY write transaction from the VIA-driven bus.
// The existing YM2149 model remains responsible for readback and
// original PSG timing. AY register 13 must remain an *event* even
// when two successive writes have the same value.
//
// A completed BDIR=1, BC=0 write phase emits one transaction.
// This avoids false write pulses when VIA control lines remain
// asserted across many 54 MHz clocks. The held-phase PA rewrite
// edge case will be characterized against real MB drivers in P2.
module mb_ay_capture (
    input  logic       clk_i,
    input  logic       reset_n_i,
    input  logic       enable_i,
    input  logic       bdir_i,
    input  logic       bc_i,
    input  logic [7:0] data_i,
    output logic       wr_o,
    output logic [3:0] reg_o,
    output logic [7:0] value_o
);
    logic [3:0] ay_reg_r;
    logic       ay_addr_valid_r;
    logic [7:0] write_data_r;
    logic       prev_write_phase_r;

    wire addr_phase_w  = bdir_i & bc_i;
    wire write_phase_w = bdir_i & !bc_i;

    always_ff @(posedge clk_i) begin
        if (!reset_n_i || !enable_i) begin
            ay_reg_r           <= 4'b0;
            ay_addr_valid_r    <= 1'b0;
            write_data_r       <= 8'h00;
            prev_write_phase_r <= 1'b0;
            wr_o               <= 1'b0;
            reg_o              <= 4'b0;
            value_o            <= 8'h00;
        end else begin
            wr_o <= 1'b0;
            if (addr_phase_w) begin
                ay_reg_r        <= data_i[3:0];
                ay_addr_valid_r <= (data_i[7:4] == 4'h0);
            end
            if (write_phase_w)
                write_data_r <= data_i;

            if (prev_write_phase_r && !write_phase_w &&
                ay_addr_valid_r) begin
                wr_o    <= 1'b1;
                reg_o   <= ay_reg_r;
                value_o <= write_data_r;
            end

            prev_write_phase_r <= write_phase_w;
        end
    end
endmodule
