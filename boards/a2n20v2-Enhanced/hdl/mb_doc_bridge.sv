// Mockingboard AY register stream -> existing Ensoniq DOC5503.
//
// P4: six note-aware multisampled voices, three left and three right.
// The DOC is exclusively owned by this core in MB mode.
// All signals are synchronous to the A2FPGA 54 MHz logic clock.
// Reuse the native YM2149 envelope generators (registers 11-13,
// all sixteen shapes and restart-on-write). AY noise is not yet modeled.
//
// The loader installs seven authentic SynthLAB piano SUSTAIN zones (5632 B),
// extracted locally from System 6.0.4 rather than redistributing the PCM.
// The original 8 KB hammer attacks are NOT looped. New discrete notes restart
// the DOC table and may receive a soft decay if AY uses a fixed volume.
// AY hardware-envelope keyboard notes retain their own native envelope.
// DOS 3.3 MCS period 0/1 ultrasonic rest markers are silent, not aliased DOC.
//
// No reconfiguration of the native IIgs/GS mode is performed here.
module mb_doc_bridge #(
    parameter int HOST_SPACING_CYCLES = 160,
    parameter int SCAN_PAUSE_CYCLES   = 4096,
    // Pitch A/B knob (same original 1024 bytes):
    // 2 = old low sustain (RTS $12), 1 = +1 octave (RTS $11),
    // 0 = +2 octaves (RTS $10). WTS stays 2 in all three cases.
    parameter logic [2:0] SUSTAIN_RES = 3'd0,
    parameter bit MULTISAMPLE_ENABLE = 1'b1,
    parameter bit PIANO_ENVELOPE_ENABLE = 1'b1,
    parameter bit REST_MUTE_ENABLE = 1'b1,
    parameter bit FX_AY_BYPASS_ENABLE = 1'b1
) (
    input  logic        clk_i,
    input  logic        reset_n_i,
    input  logic        sdram_ready_i,

    input  logic        ay_l_wr_i,
    input  logic [3:0]  ay_l_reg_i,
    input  logic [7:0]  ay_l_data_i,
    input  logic        ay_r_wr_i,
    input  logic [3:0]  ay_r_reg_i,
    input  logic [7:0]  ay_r_data_i,
    // Native YM2149 envelope timing and VIA-controlled PSG reset.
    input  logic [4:0]  ay_l_env_level_i,
    input  logic [4:0]  ay_r_env_level_i,
    input  logic        ay_l_reset_n_i,
    input  logic        ay_r_reset_n_i,

    output logic        doc_wr_o,
    output logic [7:0]  doc_addr_o,
    output logic [7:0]  doc_data_o,

    output logic        ram_wr_o,
    output logic [20:0] ram_addr_o,
    output logic [31:0] ram_data_o,
    output logic [3:0]  ram_byte_en_o,
    input  logic        ram_ready_i,

    output logic        ready_o,
    output logic [2:0]  active_voice_o,
    // Select native AY rendering for noise/multitone sound effects.
    // The FPGA still keeps the YM cores running in parallel.
    output logic        fx_ay_l_o,
    output logic        fx_ay_r_o
);
    typedef enum logic [3:0] {
        WAIT_SDRAM, RAM_FETCH, RAM_ISSUE, RAM_WAIT, RAM_RELEASE,
        ENABLE_DOC, VOICE_BEGIN, DIVIDE, VOICE_COMMAND,
        DOC_SEND, DOC_GAP, VOICE_NEXT, SCAN_PAUSE
    } state_t;

    state_t state_r, return_state_r;

    // YM2149-compatible shadow state. Only valid addresses 0..15
    // reach here; the original YM2149 still owns VIA readback.
    logic [7:0] ay_regs [0:1][0:15];

    logic [10:0] wave_word_r;
    logic [2:0] voice_r;
    logic [2:0] command_step_r;
    logic first_scan_r;
    logic [15:0] spacing_r;
    logic [15:0] pause_r;

    logic [7:0] cmd_addr_r, cmd_data_r;
    logic [15:0] voice_freq_r;
    logic [7:0] voice_volume_r;
    logic voice_tone_r;
    logic [11:0] prev_period_r [0:5];
    logic [3:0] prev_amp_r [0:5];
    logic [2:0] prev_zone_r [0:5];
    logic prev_active_r [0:5];
    logic [7:0] piano_env_r [0:5];
    logic [3:0] piano_tick_r [0:5];
    logic note_restart_r;

    // One shared, 17-clock non-restoring? No: standard restoring
    // unsigned divider, constant dividend 93623 / AY period.
    // At 8 enabled DOC oscillators (6 playing, 2 halted):
    // DOC frame = 7.15909 MHz / (8 * (8+2)).
    // FC ~= (1.022727 MHz / (16*P)) * 131072 / DOCframe
    //    ~= 93623/P for ONE period of the old 256-byte waveform.
    // Sustain PCM is 1024 bytes, but its non-identical cycles have strong
    // subharmonics. The original RES2 setting produces a four-times lower
    // table repetition rate than RES0. Expose RES as a hardware A/B
    // tuning experiment rather than assuming that the 4th spectral
    // partial is necessarily the perceptual fundamental.
    // FC stays 93623/P; RTS/SUSTAIN_RES determines the octave shift.
    logic [16:0] dividend_r, quotient_r, remainder_r;
    logic [16:0] subtract_w, shifted_remainder_w;
    logic [4:0] division_count_r;
    logic [11:0] divisor_r;
    logic [16:0] next_quotient_w;
    logic        subtract_valid_w;

    wire selected_chip_w = voice_r >= 3'd3;
    wire [1:0] selected_channel_w =
        selected_chip_w ? 2'(voice_r - 3'd3) : voice_r[1:0];
    wire [3:0] tone_lo_idx_w = {1'b0, selected_channel_w, 1'b0};
    wire [3:0] tone_hi_idx_w = tone_lo_idx_w + 4'd1;
    wire [3:0] amplitude_idx_w = 4'd8 + {2'b00, selected_channel_w};

    wire [11:0] selected_period_w = {
        ay_regs[selected_chip_w][tone_hi_idx_w][3:0],
        ay_regs[selected_chip_w][tone_lo_idx_w]
    };
    wire [7:0] selected_amp_w =
        ay_regs[selected_chip_w][amplitude_idx_w];
    wire [7:0] selected_mixer_w =
        ay_regs[selected_chip_w][7];
    wire tone_allowed_w = !selected_mixer_w[selected_channel_w];
    wire [4:0] selected_env_level_w =
        selected_chip_w ? ay_r_env_level_i : ay_l_env_level_i;
    wire selected_reset_n_w =
        selected_chip_w ? ay_r_reset_n_i : ay_l_reset_n_i;

    // Conservative zoning: preserve the calibrated C4..C5 keyboard using
    // the known-good ~Piano C3 sustain. Use other genuine source samples
    // only beyond that range until their real-hardware timbre is checked.
    // Thresholds use the AY tone period, which falls as pitch rises.
    function automatic logic [2:0] sample_zone(input logic [11:0] period);
        if (!MULTISAMPLE_ENABLE) sample_zone = 3'd3;
        else if (period <= 12'd70) sample_zone = 3'd6; // D5
        else if (period <= 12'd90) sample_zone = 3'd5; // F4
        else if (period <= 12'd112) sample_zone = 3'd4; // B3
        else if (period <= 12'd600) sample_zone = 3'd3; // C3
        else if (period <= 12'd1000) sample_zone = 3'd2; // E2
        else if (period <= 12'd1600) sample_zone = 3'd1; // G1
        else sample_zone = 3'd0;                         // C1
    endfunction

    function automatic logic [7:0] zone_wtp(input logic [2:0] zone);
        case (zone)
            3'd0: zone_wtp=8'h00; // C1, 1024 bytes
            3'd1: zone_wtp=8'h04; // G1, 1024 bytes
            3'd2: zone_wtp=8'h08; // E2, 1024 bytes
            3'd3: zone_wtp=8'h0C; // C3, 1024 bytes
            3'd4: zone_wtp=8'h10; // B3,  512 bytes
            3'd5: zone_wtp=8'h12; // F4,  512 bytes
            default:zone_wtp=8'h14; // D5, 512 bytes
        endcase
    endfunction

    // Gowin parser requires the WTS choice to be evaluated outside of a
    // concatenation. The 1KB zones use WTS=2; the upper 512B zones use WTS=1.
    wire [2:0] voice_wts_w =
        (prev_zone_r[voice_r] >= 3'd4) ? 3'd1 : 3'd2;

    wire [2:0] selected_zone_w = sample_zone(selected_period_w);
    wire selected_note_active_w = selected_reset_n_w && tone_allowed_w &&
        (!REST_MUTE_ENABLE || selected_period_w > 12'd1) &&
        (selected_amp_w[4] || |selected_amp_w[3:0]);

    wire [11:0] old_period_w = prev_period_r[voice_r];
    wire [11:0] period_delta_w =
        (selected_period_w >= old_period_w)
        ? (selected_period_w - old_period_w)
        : (old_period_w - selected_period_w);
    // >3.125% change distinguishes MCS melody steps from the introductory
    // 1-count-per-IRQ pitch glides, whose sound must NOT be retriggered.
    wire note_step_w = old_period_w >= 12'd2 &&
        ({5'b0,period_delta_w} << 5) >= {5'b0,old_period_w};
    // Music Construction Set can articulate successive SAME-PITCH notes by
    // stepping its software volume upward, without ever writing AY R13.
    // Re-strike only on a material upward amplitude step (>=3/15).
    wire amp_attack_w = !selected_amp_w[4] &&
        ({1'b0,selected_amp_w[3:0]} >=
         ({1'b0,prev_amp_r[voice_r]} + 5'd3));
    wire note_restart_w = selected_note_active_w &&
        (!prev_active_r[voice_r] || note_step_w || amp_attack_w ||
         selected_zone_w != prev_zone_r[voice_r]);

    // Bypass the piano for genuinely noise-driven AY effects, the
    // two-tone fixed-volume timer sweep and three-channel envelope effects.
    // This is tonal-instrument classification, not a hardcoded disk address.
    function automatic logic uses_ay_fx(
        input logic [7:0] mixer,
        input logic [7:0] a,
        input logic [7:0] b,
        input logic [7:0] c
    );
        uses_ay_fx =
            ((!mixer[3] && |a[4:0]) ||
             (!mixer[4] && |b[4:0]) ||
             (!mixer[5] && |c[4:0])) ||
            (mixer==8'h1C && |a[3:0] && |b[3:0]) ||
            (mixer==8'h38 && a[4] && b[4] && c[4]);
    endfunction
    assign fx_ay_l_o = FX_AY_BYPASS_ENABLE && ay_l_reset_n_i &&
        uses_ay_fx(ay_regs[0][7],ay_regs[0][8],ay_regs[0][9],ay_regs[0][10]);
    assign fx_ay_r_o = FX_AY_BYPASS_ENABLE && ay_r_reset_n_i &&
        uses_ay_fx(ay_regs[1][7],ay_regs[1][8],ay_regs[1][9],ay_regs[1][10]);

    // 5-bit upper range can occur when dividend=93623 and P=1.
    // Saturate to DOC's maximum 16-bit frequency.
    assign shifted_remainder_w =
        {remainder_r[15:0], dividend_r[16]};
    assign subtract_valid_w =
        shifted_remainder_w >= {5'b0, divisor_r};
    assign subtract_w =
        shifted_remainder_w - {5'b0, divisor_r};
    assign next_quotient_w =
        {quotient_r[15:0], subtract_valid_w};

    // The source '~Piano C3' is 1024 nonzero offset-binary samples.
    // Generated locally from the authentic synthLAB.po disk, not committed.
    // One 32-bit little-endian word per line, 256 lines total.
    //
    // Registered ROM read; RAM_FETCH waits a clock after word index changes.
    logic [31:0] synthlab_pcm_rom [0:1407];
    logic [31:0] synthlab_pcm_word_r;
    initial $readmemh("hdl/piano_multisustain.mem", synthlab_pcm_rom);
    always_ff @(posedge clk_i)
        synthlab_pcm_word_r <= synthlab_pcm_rom[wave_word_r];

    // YM2149's native 32-step DAC law, scaled to P2's 208 DOC-volume ceiling.
    function automatic logic [7:0] ym_level(input logic [4:0] amp);
        case (amp)
            5'd0: ym_level = 8'd0;
            5'd1: ym_level = 8'd1;
            5'd2: ym_level = 8'd1;
            5'd3: ym_level = 8'd2;
            5'd4: ym_level = 8'd2;
            5'd5: ym_level = 8'd2;
            5'd6: ym_level = 8'd2;
            5'd7: ym_level = 8'd3;
            5'd8: ym_level = 8'd5;
            5'd9: ym_level = 8'd6;
            5'd10: ym_level = 8'd7;
            5'd11: ym_level = 8'd8;
            5'd12: ym_level = 8'd10;
            5'd13: ym_level = 8'd11;
            5'd14: ym_level = 8'd14;
            5'd15: ym_level = 8'd15;
            5'd16: ym_level = 8'd19;
            5'd17: ym_level = 8'd22;
            5'd18: ym_level = 8'd26;
            5'd19: ym_level = 8'd30;
            5'd20: ym_level = 8'd36;
            5'd21: ym_level = 8'd43;
            5'd22: ym_level = 8'd51;
            5'd23: ym_level = 8'd58;
            5'd24: ym_level = 8'd69;
            5'd25: ym_level = 8'd83;
            5'd26: ym_level = 8'd97;
            5'd27: ym_level = 8'd111;
            5'd28: ym_level = 8'd131;
            5'd29: ym_level = 8'd157;
            5'd30: ym_level = 8'd183;
            5'd31: ym_level = 8'd208;
            default: ym_level = 8'd208;
        endcase
    endfunction

    // Byte zero of the patch corresponds to DOC address $0000.
    // The SDRAM GLU port takes a 32-bit word address and byte lanes.
    assign ram_addr_o = {10'b0, wave_word_r};
    assign ram_byte_en_o = 4'hF;
    assign ram_data_o = synthlab_pcm_word_r;
    assign ram_wr_o = (state_r == RAM_ISSUE) ||
                       (state_r == RAM_WAIT);

    assign doc_wr_o = (state_r == DOC_SEND);
    assign doc_addr_o = cmd_addr_r;
    assign doc_data_o = cmd_data_r;
    assign active_voice_o = voice_r;

    integer chip, reg_index;
    integer vi;
    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            for (chip = 0; chip < 2; chip = chip + 1)
                for (reg_index = 0; reg_index < 16;
                     reg_index = reg_index + 1)
                    ay_regs[chip][reg_index] <= 8'h00;
        end else begin
            // Mockingboard software may stop a song by pulling VIA PB2 low
            // rather than zeroing AY amplitude registers. Clear per-chip
            // shadows so stale DOC notes cannot return after PSG RESET.
            if (!ay_l_reset_n_i) begin
                for (reg_index = 0; reg_index < 16; reg_index = reg_index + 1)
                    ay_regs[0][reg_index] <= 8'h00;
            end else if (ay_l_wr_i) begin
                ay_regs[0][ay_l_reg_i] <= ay_l_data_i;
            end
            if (!ay_r_reset_n_i) begin
                for (reg_index = 0; reg_index < 16; reg_index = reg_index + 1)
                    ay_regs[1][reg_index] <= 8'h00;
            end else if (ay_r_wr_i) begin
                ay_regs[1][ay_r_reg_i] <= ay_r_data_i;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            state_r          <= WAIT_SDRAM;
            return_state_r   <= WAIT_SDRAM;
            wave_word_r      <= 11'd0;
            voice_r          <= 3'd0;
            command_step_r   <= 3'd0;
            first_scan_r     <= 1'b1;
            spacing_r        <= 16'd0;
            pause_r          <= 16'd0;
            cmd_addr_r       <= 8'h00;
            cmd_data_r       <= 8'h00;
            voice_freq_r     <= 16'h0000;
            voice_volume_r   <= 8'h00;
            voice_tone_r     <= 1'b0;
            note_restart_r    <= 1'b0;
            for (vi=0;vi<6;vi=vi+1) begin
                prev_period_r[vi] <= 12'd0;
                prev_amp_r[vi]    <= 4'd0;
                prev_zone_r[vi]   <= 3'd3;
                prev_active_r[vi] <= 1'b0;
                piano_env_r[vi]   <= 8'd0;
                piano_tick_r[vi]  <= 4'd0;
            end
            dividend_r       <= 17'd0;
            quotient_r       <= 17'd0;
            remainder_r      <= 17'd0;
            divisor_r        <= 12'd1;
            division_count_r <= 5'd0;
            ready_o          <= 1'b0;
        end else begin
            case (state_r)
                WAIT_SDRAM: begin
                    ready_o <= 1'b0;
                    if (sdram_ready_i) begin
                        wave_word_r <= 11'd0;
                        state_r <= RAM_FETCH;
                    end
                end

                RAM_FETCH: begin
                    state_r <= RAM_ISSUE;
                end

                RAM_ISSUE:
                    state_r <= RAM_WAIT;

                RAM_WAIT: begin
                    if (ram_ready_i)
                        state_r <= RAM_RELEASE;
                end

                RAM_RELEASE: begin
                    // Drop WR for one full clock to re-arm SDRAM's
                    // rising-edge request capture before next word.
                    if (wave_word_r == 11'd1407) begin
                        state_r <= ENABLE_DOC;
                    end else begin
                        wave_word_r <= wave_word_r + 1'b1;
                        state_r <= RAM_FETCH;
                    end
                end

                ENABLE_DOC: begin
                    // E1 = $0E enables oscillators 0..7.
                    // Only 0..5 are unhalted; the last two remain idle.
                    cmd_addr_r <= 8'hE1;
                    cmd_data_r <= 8'h0E;
                    return_state_r <= VOICE_BEGIN;
                    voice_r <= 3'd0;
                    state_r <= DOC_SEND;
                end

                VOICE_BEGIN: begin
                    // Live AY shadow captures take effect at the next
                    // voice scan, not asynchronously in the DOC.
                    voice_tone_r <= tone_allowed_w;
                    note_restart_r <= note_restart_w;
                    prev_active_r[voice_r] <= selected_note_active_w;
                    prev_period_r[voice_r] <= selected_period_w;
                    prev_amp_r[voice_r] <= selected_amp_w[4] ? 4'd0 : selected_amp_w[3:0];
                    prev_zone_r[voice_r] <= selected_zone_w;
                    if (!selected_note_active_w) begin
                        piano_env_r[voice_r] <= 8'd0;
                        piano_tick_r[voice_r] <= 4'd0;
                    end else if (note_restart_w) begin
                        piano_env_r[voice_r] <= 8'hFF;
                        piano_tick_r[voice_r] <= 4'd0;
                    end else if (!selected_amp_w[4] && PIANO_ENVELOPE_ENABLE) begin
                        if (piano_tick_r[voice_r] == 4'd15) begin
                            piano_tick_r[voice_r] <= 4'd0;
                            if (piano_env_r[voice_r] != 8'd0)
                                piano_env_r[voice_r] <= piano_env_r[voice_r] - 1'b1;
                        end else piano_tick_r[voice_r] <= piano_tick_r[voice_r]+1'b1;
                    end
                    // AY amplitude bit 4 selects the actual, clocked 32-step
                    // envelope from the existing YM2149 core. Fixed levels
                    // share the logarithmic law; RESET/tone-off force mute.
                    // Do not reshape the keyboard's real AY R13 envelope.
                    // Fixed-volume MCS notes get a mild one-shot piano decay.
                    voice_volume_r <= selected_note_active_w ?
                        ((selected_amp_w[4] || !PIANO_ENVELOPE_ENABLE) ?
                            ym_level(selected_amp_w[4] ? selected_env_level_w :
                                     {selected_amp_w[3:0],selected_amp_w[3]}) :
                            8'((({8'b0,ym_level({selected_amp_w[3:0],selected_amp_w[3]})}
                                * {8'b0,(note_restart_w ? 8'hFF : piano_env_r[voice_r])})
                                + 16'd255) >> 8)) :
                        8'd0;
                    divisor_r <= (selected_period_w == 12'd0) ?
                                  12'd1 : selected_period_w;
                    dividend_r <= 17'd93623;
                    quotient_r <= 17'd0;
                    remainder_r <= 17'd0;
                    division_count_r <= 5'd17;
                    state_r <= DIVIDE;
                end

                DIVIDE: begin
                    remainder_r <= subtract_valid_w ?
                                   subtract_w : shifted_remainder_w;
                    dividend_r <= {dividend_r[15:0], 1'b0};
                    quotient_r <= next_quotient_w;
                    division_count_r <= division_count_r - 1'b1;
                    if (division_count_r == 5'd1) begin
                        // Keep FC unchanged; vary only the DOC resolution in RTS.
                        voice_freq_r <= next_quotient_w[16] ?
                                        16'hFFFF :
                                        next_quotient_w[15:0];
                        command_step_r <= (first_scan_r || note_restart_r) ? 3'd0 : 3'd3;
                        state_r <= VOICE_COMMAND;
                    end
                end

                VOICE_COMMAND: begin
                    // INIT: HALT, WTP, RTS. Every scan: FL, FH,
                    // VOL, CTRL. Avoid retriggering oscillators
                    // each scan by not repeating the HALT command.
                    case (command_step_r)
                        3'd0: begin
                            cmd_addr_r <= 8'hA0 + {5'b0, voice_r};
                            cmd_data_r <= (voice_r < 3'd3) ?
                                          8'h11 : 8'h01;
                        end
                        3'd1: begin
                            cmd_addr_r <= 8'h80 + {5'b0, voice_r};
                            cmd_data_r <= zone_wtp(prev_zone_r[voice_r]);
                        end
                        3'd2: begin
                            cmd_addr_r <= 8'hC0 + {5'b0, voice_r};
                            cmd_data_r <= {2'b00, voice_wts_w, SUSTAIN_RES};
                        end
                        3'd3: begin
                            cmd_addr_r <= 8'h00 + {5'b0, voice_r};
                            cmd_data_r <= voice_freq_r[7:0];
                        end
                        3'd4: begin
                            cmd_addr_r <= 8'h20 + {5'b0, voice_r};
                            cmd_data_r <= voice_freq_r[15:8];
                        end
                        3'd5: begin
                            cmd_addr_r <= 8'h40 + {5'b0, voice_r};
                            cmd_data_r <= voice_volume_r;
                        end
                        default: begin
                            cmd_addr_r <= 8'hA0 + {5'b0, voice_r};
                            cmd_data_r <= (voice_r < 3'd3) ?
                                         ((voice_volume_r != 8'd0) ?
                                          8'h10 : 8'h11) :
                                         ((voice_volume_r != 8'd0) ?
                                          8'h00 : 8'h01);
                        end
                    endcase
                    return_state_r <= VOICE_NEXT;
                    state_r <= DOC_SEND;
                end

                DOC_SEND: begin
                    // One logic-clock-wide /CS pulse. doc5503's
                    // own host state machine accepts the command
                    // in a later oscillator slot; space writes.
                    spacing_r <= 16'(HOST_SPACING_CYCLES);
                    state_r <= DOC_GAP;
                end

                DOC_GAP: begin
                    if (spacing_r == 16'd0)
                        state_r <= return_state_r;
                    else
                        spacing_r <= spacing_r - 1'b1;
                end

                VOICE_NEXT: begin
                    if (command_step_r == 3'd6) begin
                        if (voice_r == 3'd5) begin
                            voice_r <= 3'd0;
                            first_scan_r <= 1'b0;
                            ready_o <= 1'b1;
                            pause_r <= 16'(SCAN_PAUSE_CYCLES);
                            state_r <= SCAN_PAUSE;
                        end else begin
                            voice_r <= voice_r + 1'b1;
                            state_r <= VOICE_BEGIN;
                        end
                    end else begin
                        command_step_r <= command_step_r + 1'b1;
                        state_r <= VOICE_COMMAND;
                    end
                end

                SCAN_PAUSE: begin
                    if (pause_r == 16'd0)
                        state_r <= VOICE_BEGIN;
                    else
                        pause_r <= pause_r - 1'b1;
                end

                default:
                    state_r <= WAIT_SDRAM;
            endcase
        end
    end
endmodule
