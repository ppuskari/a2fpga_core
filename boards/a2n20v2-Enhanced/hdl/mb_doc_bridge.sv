// Mockingboard AY register stream -> existing Ensoniq DOC5503.
//
// P2 first-tone implementation: six pitched voices, 3L + 3R.
// The DOC is exclusively owned by this core in MB mode.
// All signals are synchronous to the A2FPGA 54 MHz logic clock.
// Reuse the native YM2149 envelope generators (registers 11-13,
// all sixteen shapes and restart-on-write). AY noise is not yet modeled.
//
// The loader populates the first 256 bytes of native sound SDRAM
// with a nonzero, offset-binary piano-like looped PCM wavetable. DOC
// sample $00 means STOP, so each of the 256 sample bytes is nonzero.
//
// No reconfiguration of the native IIgs/GS mode is performed here.
module mb_doc_bridge #(
    parameter int HOST_SPACING_CYCLES = 160,
    parameter int SCAN_PAUSE_CYCLES   = 4096
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
    output logic [2:0]  active_voice_o
);
    typedef enum logic [3:0] {
        WAIT_SDRAM, RAM_ISSUE, RAM_WAIT, RAM_RELEASE,
        ENABLE_DOC, VOICE_BEGIN, DIVIDE, VOICE_COMMAND,
        DOC_SEND, DOC_GAP, VOICE_NEXT, SCAN_PAUSE
    } state_t;

    state_t state_r, return_state_r;

    // YM2149-compatible shadow state. Only valid addresses 0..15
    // reach here; the original YM2149 still owns VIA readback.
    logic [7:0] ay_regs [0:1][0:15];

    logic [5:0] wave_word_r;
    logic [2:0] voice_r;
    logic [2:0] command_step_r;
    logic first_scan_r;
    logic [15:0] spacing_r;
    logic [15:0] pause_r;

    logic [7:0] cmd_addr_r, cmd_data_r;
    logic [15:0] voice_freq_r;
    logic [7:0] voice_volume_r;
    logic voice_tone_r;

    // One shared, 17-clock non-restoring? No: standard restoring
    // unsigned divider, constant dividend 93623 / AY period.
    // At 8 enabled DOC oscillators (6 playing, 2 halted):
    // DOC frame = 7.15909 MHz / (8 * (8+2)).
    // FC ~= (1.022727 MHz / (16*P)) * 131072 / DOCframe
    //    ~= 93623/P. Clamp FC for AY period 0 or 1.
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

    // PIANO-WAVETABLE EXPERIMENT: 256 bytes of original, modeled piano
    // steady-state PCM (12 tuned partials). This is a compact *looped*
    // timbre, NOT a multisample of a recorded acoustic piano and NOT an
    // attack/sustain envelope. The native YM envelope still drives volume.
    // Pack four consecutive unsigned offset-binary bytes in each little-
    // endian SDRAM word. Do NOT store $00: the DOC interprets $00 as HALT.
    // This case ROM is generated from a deterministic harmonic model.
    // FNV-1a of 256 bytes, ascending address: 32'hB4D62B32.
    function automatic logic [31:0] piano_word(input logic [5:0] index);
        case (index)
            6'd0: piano_word = 32'hA1968B7F;
            6'd1: piano_word = 32'hC6BEB5AB;
            6'd2: piano_word = 32'hDDD9D3CD;
            6'd3: piano_word = 32'hE8E6E4E1;
            6'd4: piano_word = 32'hEBEBEAE9;
            6'd5: piano_word = 32'hEDECECEC;
            6'd6: piano_word = 32'hEEEEEDED;
            6'd7: piano_word = 32'hEDEEEEEE;
            6'd8: piano_word = 32'hEBECECED;
            6'd9: piano_word = 32'hE8E8E9EA;
            6'd10: piano_word = 32'hE4E5E6E7;
            6'd11: piano_word = 32'hE1E2E3E3;
            6'd12: piano_word = 32'hDEDFDFE0;
            6'd13: piano_word = 32'hD9DADBDC;
            6'd14: piano_word = 32'hD4D5D7D8;
            6'd15: piano_word = 32'hD1D1D2D3;
            6'd16: piano_word = 32'hCECECFD0;
            6'd17: piano_word = 32'hCBCCCCCD;
            6'd18: piano_word = 32'hC6C7C8CA;
            6'd19: piano_word = 32'hC0C2C3C5;
            6'd20: piano_word = 32'hBABCBDBF;
            6'd21: piano_word = 32'hB5B6B8B9;
            6'd22: piano_word = 32'hB1B2B3B4;
            6'd23: piano_word = 32'hACAEAFB0;
            6'd24: piano_word = 32'hA7A9AAAB;
            6'd25: piano_word = 32'hA2A3A5A6;
            6'd26: piano_word = 32'h9C9E9FA1;
            6'd27: piano_word = 32'h9597999B;
            6'd28: piano_word = 32'h8C8F9193;
            6'd29: piano_word = 32'h8184878A;
            6'd30: piano_word = 32'h777A7C7F;
            6'd31: piano_word = 32'h70717375;
            6'd32: piano_word = 32'h6D6D6E6F;
            6'd33: piano_word = 32'h6D6D6D6D;
            6'd34: piano_word = 32'h6F6E6E6E;
            6'd35: piano_word = 32'h6F6F6F6F;
            6'd36: piano_word = 32'h6E6F6F6F;
            6'd37: piano_word = 32'h6C6D6D6E;
            6'd38: piano_word = 32'h67696A6B;
            6'd39: piano_word = 32'h62636566;
            6'd40: piano_word = 32'h5B5D5E60;
            6'd41: piano_word = 32'h54565759;
            6'd42: piano_word = 32'h4E505153;
            6'd43: piano_word = 32'h494A4B4D;
            6'd44: piano_word = 32'h44454647;
            6'd45: piano_word = 32'h3E404142;
            6'd46: piano_word = 32'h393A3C3D;
            6'd47: piano_word = 32'h34353638;
            6'd48: piano_word = 32'h2F303133;
            6'd49: piano_word = 32'h2A2B2C2E;
            6'd50: piano_word = 32'h25262729;
            6'd51: piano_word = 32'h21222324;
            6'd52: piano_word = 32'h1D1E1F20;
            6'd53: piano_word = 32'h1A1B1C1C;
            6'd54: piano_word = 32'h16171819;
            6'd55: piano_word = 32'h13141415;
            6'd56: piano_word = 32'h11111212;
            6'd57: piano_word = 32'h10101010;
            6'd58: piano_word = 32'h10101010;
            6'd59: piano_word = 32'h12111111;
            6'd60: piano_word = 32'h19171513;
            6'd61: piano_word = 32'h2A25201C;
            6'd62: piano_word = 32'h4A413831;
            6'd63: piano_word = 32'h74695E53;
            default: piano_word = 32'h80808080;
        endcase
    endfunction

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
    assign ram_addr_o = {15'b0, wave_word_r};
    assign ram_byte_en_o = 4'hF;
    assign ram_data_o = piano_word(wave_word_r);
    assign ram_wr_o = (state_r == RAM_ISSUE) ||
                       (state_r == RAM_WAIT);

    assign doc_wr_o = (state_r == DOC_SEND);
    assign doc_addr_o = cmd_addr_r;
    assign doc_data_o = cmd_data_r;
    assign active_voice_o = voice_r;

    integer chip, reg_index;
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
            wave_word_r      <= 6'd0;
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
                        wave_word_r <= 6'd0;
                        state_r <= RAM_ISSUE;
                    end
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
                    if (wave_word_r == 6'd63) begin
                        state_r <= ENABLE_DOC;
                    end else begin
                        wave_word_r <= wave_word_r + 1'b1;
                        state_r <= RAM_ISSUE;
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
                    // AY amplitude bit 4 selects the actual, clocked 32-step
                    // envelope from the existing YM2149 core. Fixed levels
                    // share the logarithmic law; RESET/tone-off force mute.
                    voice_volume_r <=
                        (selected_reset_n_w && tone_allowed_w) ?
                        ym_level(selected_amp_w[4] ? selected_env_level_w :
                                 {selected_amp_w[3:0],selected_amp_w[3]}) :
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
                        voice_freq_r <= next_quotient_w[16] ?
                                        16'hFFFF :
                                        next_quotient_w[15:0];
                        command_step_r <= first_scan_r ? 3'd0 : 3'd3;
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
                            cmd_data_r <= 8'h00;
                        end
                        3'd2: begin
                            cmd_addr_r <= 8'hC0 + {5'b0, voice_r};
                            cmd_data_r <= 8'h00; // 256-byte table, RES0
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
