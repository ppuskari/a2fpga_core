// Mockingboard AY register stream -> existing Ensoniq DOC5503.
//
// P2 first-tone implementation: six pitched voices, 3L + 3R.
// The DOC is exclusively owned by this core in MB mode.
// All signals are synchronous to the A2FPGA 54 MHz logic clock.
// AY envelopes and noise are deliberately NOT supported yet.
//
// The loader populates the first 256 bytes of native sound SDRAM
// with a nonzero, offset-binary triangle waveform. DOC sample $00
// means STOP (not zero amplitude), so every wavetable byte is nonzero.
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

    function automatic logic [7:0] triangle_byte(
        input logic [7:0] phase
    );
        logic [7:0] ramp;
        begin
            ramp = {phase[5:0], 1'b0};
            case (phase[7:6])
                2'b00: triangle_byte = 8'h81 + ramp;
                2'b01: triangle_byte = 8'hFF - ramp;
                2'b10: triangle_byte = 8'h7F - ramp;
                default: triangle_byte = 8'h01 + ramp;
            endcase
        end
    endfunction

    function automatic logic [7:0] ay_level(input logic [3:0] amp);
        case (amp)
            4'd0:  ay_level = 8'd0;
            4'd1:  ay_level = 8'd1;
            4'd2:  ay_level = 8'd1;
            4'd3:  ay_level = 8'd2;
            4'd4:  ay_level = 8'd3;
            4'd5:  ay_level = 8'd5;
            4'd6:  ay_level = 8'd7;
            4'd7:  ay_level = 8'd11;
            4'd8:  ay_level = 8'd16;
            4'd9:  ay_level = 8'd24;
            4'd10: ay_level = 8'd35;
            4'd11: ay_level = 8'd50;
            4'd12: ay_level = 8'd72;
            4'd13: ay_level = 8'd102;
            4'd14: ay_level = 8'd146;
            default: ay_level = 8'd208;
        endcase
    endfunction

    // Byte zero of the patch corresponds to DOC address $0000.
    // The SDRAM GLU port takes a 32-bit word address and byte lanes.
    assign ram_addr_o = {15'b0, wave_word_r};
    assign ram_byte_en_o = 4'hF;
    assign ram_data_o = {
        triangle_byte({wave_word_r, 2'b11}),
        triangle_byte({wave_word_r, 2'b10}),
        triangle_byte({wave_word_r, 2'b01}),
        triangle_byte({wave_word_r, 2'b00})
    };
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
            if (ay_l_wr_i)
                ay_regs[0][ay_l_reg_i] <= ay_l_data_i;
            if (ay_r_wr_i)
                ay_regs[1][ay_r_reg_i] <= ay_r_data_i;
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
                    voice_volume_r <=
                        tone_allowed_w ?
                        ay_level(selected_amp_w[4] ?
                                 4'hF : selected_amp_w[3:0]) : 8'd0;
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
