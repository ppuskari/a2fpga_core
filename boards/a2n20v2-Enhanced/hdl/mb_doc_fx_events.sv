// M6.5a: AY/Mockingboard effects event decoder feeding the future
// Ensoniq DOC OSC6/7 sample player. NO audio is generated in this stage.
//
// Design rules:
//   * Immediate VIA/AY semantics and the six golden piano voices unchanged.
//   * Examine only coherently published AY register snapshots.
//   * Preserve simultaneous tone/noise mixer and envelope-mode semantics.
//   * AY R13 writes retrigger an envelope even if the written shape repeats.
//   * Independent left and right chip effects, not whole-chip audio bypass.
//   * Event valid is a one-clk pulse; future FX engine must queue it.
// This module intentionally never assumes an AY register contains an
// instrument ID: percussion mapping is a tunable policy, not hardware truth.
module mb_doc_fx_events #(
    parameter bit ENABLE = 1'b0,
    parameter integer NOISE_MOD_COOLDOWN_CYCLES = 270000 // 5ms at 54MHz
)(
    input wire clk_i,
    input wire reset_n_i,
    input wire [1:0] chip_reset_n_i,
    input wire [1:0] publish_i,
    input wire [1:0] r13_write_i,
    input wire [1:0][7:0] mixer_i,
    input wire [1:0][4:0] noise_period_i,
    input wire [1:0][2:0][4:0] amp_i,
    input wire [1:0][4:0] env_level_i,
    input wire [1:0][3:0] env_shape_i,
    output reg [1:0] event_valid_o,
    output reg [1:0][2:0] event_patch_o,
    output reg [1:0][7:0] event_velocity_o,
    output reg [1:0][2:0] event_noise_mask_o,
    output reg [1:0][2:0] event_tone_mask_o,
    output reg [1:0][2:0] event_envelope_mask_o,
    output reg [1:0][4:0] event_noise_period_o,
    output reg [1:0][3:0] event_envelope_shape_o
);
    // Patch 0=explosion, 1=kick, 2=snare, 3=tom,
    // 4=hihat, 5=laser, 6=cymbal. Classification is heuristic
    // until a score-aware profile assigns an explicit patch.
    localparam integer CW = NOISE_MOD_COOLDOWN_CYCLES < 2 ?
        1 : $clog2(NOISE_MOD_COOLDOWN_CYCLES+1);
    reg [1:0] prev_noise_active_r;
    reg [1:0][7:0] prev_energy_r;
    reg [1:0][4:0] prev_noise_period_r;
    reg [1:0] r13_pending_r;
    reg [CW-1:0] cooldown_r[0:1];

    wire [1:0][2:0] noise_mask_w, tone_mask_w, env_mask_w;
    wire [1:0][7:0] energy_w;
    wire [1:0] noise_active_w, tone_active_w;
    genvar chip;
    generate for (chip=0; chip<2; chip=chip+1) begin : gen_channel_decode
        wire [2:0] live;
        for (genvar c=0;c<3;c=c+1) begin : gen_channel
            // An envelope-controlled channel remains eligible even while
            // the instantaneous envelope level is zero.
            assign live[c] = amp_i[chip][c][4] ||
                              (|amp_i[chip][c][3:0]);
            assign noise_mask_w[chip][c] =
                ~mixer_i[chip][3+c] && live[c];
            assign tone_mask_w[chip][c] =
                ~mixer_i[chip][c] && live[c];
            assign env_mask_w[chip][c] =
                amp_i[chip][c][4] && live[c];
        end
        assign noise_active_w[chip] = |noise_mask_w[chip];
        assign tone_active_w[chip] = |tone_mask_w[chip];

        // Generate-time indexing avoids Icarus' variable packed-array
        // part-select restriction and avoids a runtime priority loop.
        wire [7:0] channel_level_w [0:2];
        for (genvar c=0;c<3;c=c+1) begin : gen_amplitude
            assign channel_level_w[c] = amp_i[chip][c][4] ?
                ({3'b0, env_level_i[chip]} << 3) :
                ({4'b0, amp_i[chip][c][3:0]} << 4);
        end
        wire [7:0] noise_level_a_w =
            noise_mask_w[chip][0] ? channel_level_w[0] : 8'd0;
        wire [7:0] noise_level_b_w =
            noise_mask_w[chip][1] ? channel_level_w[1] : 8'd0;
        wire [7:0] noise_level_c_w =
            noise_mask_w[chip][2] ? channel_level_w[2] : 8'd0;
        wire [7:0] max_ab_w =
            noise_level_a_w > noise_level_b_w ?
            noise_level_a_w : noise_level_b_w;
        assign energy_w[chip] =
            max_ab_w > noise_level_c_w ? max_ab_w : noise_level_c_w;
    end endgenerate

    function automatic [2:0] choose_patch(
        input logic [4:0] period,
        input logic [2:0] tone_mask,
        input logic [2:0] envelope_mask
    );
        if (|tone_mask)
            choose_patch = (period <= 5'd7) ? 3'd1 : 3'd5;
        else if (period <= 5'd4)
            choose_patch = 3'd4;
        else if (period <= 5'd10)
            choose_patch = 3'd2;
        else if (period <= 5'd18)
            choose_patch = (|envelope_mask) ? 3'd0 : 3'd3;
        else
            choose_patch = (|envelope_mask) ? 3'd0 : 3'd6;
    endfunction

    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            event_valid_o <= 2'b00;
            event_patch_o <= '0;
            event_velocity_o <= '0;
            event_noise_mask_o <= '0;
            event_tone_mask_o <= '0;
            event_envelope_mask_o <= '0;
            event_noise_period_o <= '0;
            event_envelope_shape_o <= '0;
            prev_noise_active_r <= '0;
            prev_energy_r <= '0;
            prev_noise_period_r <= '0;
            r13_pending_r <= '0;
            for(integer i=0;i<2;i=i+1)
                cooldown_r[i] <= '0;
        end else begin
            event_valid_o <= 2'b00;
            for(integer i=0;i<2;i=i+1) begin
                if (!chip_reset_n_i[i]) begin
                    prev_noise_active_r[i] <= 1'b0;
                    prev_energy_r[i] <= 8'd0;
                    prev_noise_period_r[i] <= 5'd0;
                    r13_pending_r[i] <= 1'b0;
                    cooldown_r[i] <= '0;
                end else begin
                    if (cooldown_r[i] != '0)
                        cooldown_r[i] <= cooldown_r[i] - 1'b1;
                    if (r13_write_i[i])
                        r13_pending_r[i] <= 1'b1;
                    if (publish_i[i]) begin
                        // Only noise-bearing channels are FX candidates;
                        // normal tone-only piano notes never trigger OSC6/7.
                        if (ENABLE && noise_active_w[i] &&
                            (!prev_noise_active_r[i] ||
                            (energy_w[i] > prev_energy_r[i] &&
                             energy_w[i]-prev_energy_r[i] >= 8'd32) ||
                            r13_pending_r[i] ||
                            r13_write_i[i] ||
                            (noise_period_i[i] != prev_noise_period_r[i] &&
                             cooldown_r[i] == '0))) begin
                            event_valid_o[i] <= 1'b1;
                            event_patch_o[i] <= choose_patch(
                                noise_period_i[i], tone_mask_w[i], env_mask_w[i]);
                            event_velocity_o[i] <= energy_w[i];
                            event_noise_mask_o[i] <= noise_mask_w[i];
                            event_tone_mask_o[i] <= tone_mask_w[i];
                            event_envelope_mask_o[i] <= env_mask_w[i];
                            event_noise_period_o[i] <= noise_period_i[i];
                            event_envelope_shape_o[i] <= env_shape_i[i];
                            cooldown_r[i] <= CW'(NOISE_MOD_COOLDOWN_CYCLES);
                        end
                        prev_noise_active_r[i] <= noise_active_w[i];
                        prev_energy_r[i] <= energy_w[i];
                        prev_noise_period_r[i] <= noise_period_i[i];
                        r13_pending_r[i] <= 1'b0;
                    end
                end
            end
        end
    end
endmodule
