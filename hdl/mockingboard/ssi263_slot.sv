// Experimental Mockingboard C single SSI-263 socket, slot address $Cn40-$Cn7F.
// Physical chip select: A6=1, A7=0; A0..A2 are register-select lines.
// The ordinary Mockingboard's dual 6522 windows are preserved outside speech
// selection. Demo Disk 1 uses right VIA CA1 ($C48D/$C48E) for A/R.
// Reference: kue-m/mockingboard-pico bus interface (MIT, Kitcat, 2026).
//
// P1 retains the P0 CPU bus, status and IRQ timing and adds an original
// experimental FPGA-only formant wavetable speech approximation. It is not
// a transistor-accurate voice reproduction; verify on physical hardware.
module ssi263_slot #(
    parameter integer VOICE_PROFILE = 1
) (
    input  wire       clk_i,
    input  wire       reset_n_i,
    input  wire       enabled_i,
    input  wire       card_io_sel_i,
    input  wire       xck_tick_i,
    input  wire       data_in_strobe_i,
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
    wire [7:0] debug_r3_w;
    logic [7:0] debug_powerup_count_r;
    logic powered_prev_r;

    // P2 hardware-only diagnostics: non-destructive read overlays at
    // $Cn41-$Cn44. CPU writes retain their original SSI-263 semantics.
    // Counters saturate instead of wrapping so long BASIC delays are useful.
    logic [7:0] diag_wr_count_r;
    logic [7:0] diag_xck_count_r;
    always @(posedge clk_i) begin
        if (!reset_n_i || !enabled_i) begin
            diag_wr_count_r <= 8'd0;
            diag_xck_count_r <= 8'd0;
            debug_powerup_count_r <= 8'd0;
            powered_prev_r <= 1'b0;
        end else begin
            if (wr_pulse_r && diag_wr_count_r != 8'hFF)
                diag_wr_count_r <= diag_wr_count_r + 8'd1;
            if (xck_tick_i && diag_xck_count_r != 8'hFF)
                diag_xck_count_r <= diag_xck_count_r + 8'd1;
            powered_prev_r <= powered_o;
            if (powered_o && !powered_prev_r && debug_powerup_count_r != 8'hFF)
                debug_powerup_count_r <= debug_powerup_count_r + 8'd1;
        end
    end

    // The bridge presents address/RW before it fetches the actual CPU data.
    // Wait for its data_in_strobe: data_i is then the newly latched byte.
    // The prior wr_phase rising-edge sampler captured stale READ data ($A5).
    always @(posedge clk_i) begin
        if (!reset_n_i || !enabled_i) begin
            wr_prev_r <= 1'b0;
            wr_pulse_r <= 1'b0;
            wr_reg_r <= 3'b0;
            wr_data_r <= 8'h00;
        end else begin
            // Arm only when the data-valid strobe is actually present.
            // Prior address-select cycles must not consume the edge.
            wr_prev_r <= wr_phase_w && data_in_strobe_i;
            wr_pulse_r <= wr_phase_w && data_in_strobe_i && !wr_prev_r;
            if (wr_phase_w && data_in_strobe_i && !wr_prev_r) begin
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
        .phoneme_start_o(phoneme_start_w),
        .debug_r3_o(debug_r3_w)
    );

    ssi263_voice #(.VOICE_PROFILE(VOICE_PROFILE)) voice (
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
    // Preserve original $Cn40 status. Read-only diagnostic overlay:
    // $Cn41 accepted CPU writes (saturating)
    // $Cn42 Apple PHI/XCK ticks (saturating)
    // $Cn43 fixed signature $A5 (proves read-selection path)
    // $Cn44 powered state (bit 0)
    // $Cn45 last latched SSI write register address (0..7)
    // $Cn46 last latched SSI write data
    // $Cn47 internal SSI R3 register state
    // $Cn48 power-up transition counter (saturates at 255)
    // These do not alter SSI writes, IRQ, timers, or audio behavior.
    assign speech_data_o =
        (card_addr_i[2:0] == 3'd1) ? diag_wr_count_r :
        (card_addr_i[2:0] == 3'd2) ? diag_xck_count_r :
        (card_addr_i[2:0] == 3'd3) ? 8'hA5 :
        (card_addr_i[3:0] == 4'h8) ? debug_powerup_count_r :
        (card_addr_i[2:0] == 3'd4) ? {7'b0,powered_o} :
        (card_addr_i[2:0] == 3'd5) ? {5'b0,wr_reg_r} :
        (card_addr_i[2:0] == 3'd6) ? wr_data_r :
        (card_addr_i[2:0] == 3'd7) ? debug_r3_w :
                                   {ar_status_w,7'b0};
    // VIA observes the physical active-low A/R line; its falling-edge
    // detector latches IFR bit 1 when a phoneme requests the next one.
    assign via_ca1_o = enabled_i ? ar_n_w : 1'b1;
endmodule
