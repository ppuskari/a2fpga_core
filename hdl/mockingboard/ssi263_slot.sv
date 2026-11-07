// Experimental Mockingboard C single SSI-263 socket, slot address $Cn40-$Cn7F.
// Physical chip select: A6=1, A7=0; A0..A2 are register-select lines.
// The ordinary Mockingboard's dual 6522 windows are preserved outside speech
// selection. A/R pin is wired to the LEFT VIA CA1 input.
// Reference: kue-m/mockingboard-pico bus interface (MIT, Kitcat, 2026).
//
// P1 retains the P0 CPU bus, status and IRQ timing and adds an original
// experimental FPGA-only formant wavetable speech approximation. It is not
// a transistor-accurate voice reproduction; verify on physical hardware.
module ssi263_slot (
    input  wire       clk_i,
    input  wire       reset_n_i,
    input  wire       enabled_i,
    input  wire       card_io_sel_i,
    input  wire       xck_tick_i,
    input  wire       rw_n_i,
    input  wire [7:0] card_addr_i,
    input  wire [7:0] data_i,

    output wire       speech_selected_o,
    output wire       speech_read_o,
    output wire [7:0] speech_data_o,
    output wire       via_ca1_o,
    output wire       powered_o,
    output wire [5:0] phoneme_o,
    output wire signed [15:0] speech_pcm_o
);
    wire speech_sel_w = enabled_i && card_io_sel_i &&
                        (card_addr_i[7:6] == 2'b01);
    wire wr_phase_w = speech_sel_w && !rw_n_i;
    logic wr_prev_r, wr_pulse_r;
    logic [2:0] wr_reg_r;
    logic [7:0] wr_data_r;
    wire ar_n_w, ar_status_w, phoneme_start_w;
    wire [3:0] amplitude_w;
    wire [7:0] inflection_w, rate_w;

    // The Apple slot bus holds an I/O write throughout a PHI0 window.
    // Generate exactly one strobe per distinct bus write, not one per
    // 54 MHz clock. The captured data is stable before the next clock.
    always @(posedge clk_i) begin
        if (!reset_n_i || !enabled_i) begin
            wr_prev_r <= 1'b0;
            wr_pulse_r <= 1'b0;
            wr_reg_r <= 3'b0;
            wr_data_r <= 8'h00;
        end else begin
            wr_prev_r <= wr_phase_w;
            wr_pulse_r <= wr_phase_w && !wr_prev_r;
            if (wr_phase_w && !wr_prev_r) begin
                wr_reg_r <= card_addr_i[2:0];
                wr_data_r <= data_i;
            end
        end
    end

    ssi263_control core (
        .clk_i(clk_i),
        .reset_n_i(reset_n_i && enabled_i),
        .xck_tick_i(xck_tick_i && enabled_i),
        .wr_i(wr_pulse_r),
        .addr_i(wr_reg_r),
        .data_i(wr_data_r),
        .ar_n_o(ar_n_w),
        .status_d7_o(ar_status_w),
        .powered_o(powered_o),
        .phoneme_o(phoneme_o),
        .amplitude_o(amplitude_w),
        .inflection_o(inflection_w),
        .rate_o(rate_w),
        .phoneme_start_o(phoneme_start_w)
    );

    ssi263_voice voice (
        .clk_i(clk_i),
        .reset_n_i(reset_n_i && enabled_i),
        .powered_i(powered_o),
        .phoneme_start_i(phoneme_start_w),
        .phoneme_i(phoneme_o),
        .amplitude_i(amplitude_w),
        .inflection_i(inflection_w),
        .rate_i(rate_w),
        .pcm_o(speech_pcm_o)
    );

    assign speech_selected_o = speech_sel_w;
    assign speech_read_o = speech_sel_w && rw_n_i;
    // D7 is meaningful; retain the existing zero convention for D6..D0.
    assign speech_data_o = {ar_status_w, 7'b0};
    // VIA observes the physical active-low A/R line; its falling-edge
    // detector latches IFR bit 1 when a phoneme requests the next one.
    assign via_ca1_o = enabled_i ? ar_n_w : 1'b1;
endmodule
