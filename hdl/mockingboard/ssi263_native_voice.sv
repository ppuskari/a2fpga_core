// P7 native SSI-263 FPGA development engine.
// NON-FIDELITY DIAGNOSTIC: source generation only. NOT a formant-accurate
// recreation of the SSI-263 switched-capacitor filter chain.
// The ROM fields are real decoded silicon data; DSP remains under development.
// All synthesis runs on FPGA clk_i and feeds independent 16-bit HDMI PCM.
// There is no MCU dependency and no Ensoniq DOC usage.
module ssi263_native_voice #(
    parameter integer CLK_HZ = 54000000,
    parameter integer SAMPLE_HZ = 16000
)(
    input wire clk_i,
    input wire reset_n_i,
    input wire powered_i,
    input wire phoneme_start_i,
    input wire [5:0] phoneme_i,
    input wire [3:0] amplitude_i,
    input wire [7:0] inflection_i,
    input wire [7:0] rate_i,
    output reg signed [15:0] pcm_o
);
    localparam integer DIV = CLK_HZ / SAMPLE_HZ;
    localparam integer DW = $clog2(DIV);
    reg [DW-1:0] div_r;
    reg [15:0] phase_r;
    reg [15:0] lfsr_r;
    reg signed [17:0] lp_r;
    wire [28:0] params_w;
    ssi263_native_rom rom(.phoneme_i(phoneme_i),.params_o(params_w));
    wire [3:0] fa_w = params_w[23:20];
    wire [3:0] va_w = params_w[19:16];
    wire voiced_w = !params_w[24];
    wire fric_w = !params_w[25];
    // Only a diagnostic excitation generator. Pitch is NOT yet the
    // 12-bit SSI-263 inflection equation (R1 and R2 must be combined).
    wire [15:0] step_w = 16'd300 + {8'd0,inflection_i} +
                         {12'd0,rate_i[3:0]};
    wire signed [8:0] noise_w = $signed({1'b0,lfsr_r[7:0]}) - 9'sd128;
    wire signed [8:0] pulse_w = phase_r[15] ? -9'sd128 : 9'sd127;
    wire signed [16:0] vocal_w = voiced_w ?
                    ($signed(pulse_w) * $signed({1'b0,va_w})) : 17'sd0;
    wire signed [16:0] fricative_w = fric_w ?
                    ($signed(noise_w) * $signed({1'b0,fa_w})) : 17'sd0;
    wire signed [18:0] mixed_w = ($signed(vocal_w) + $signed(fricative_w)) *
                                  $signed({1'b0,amplitude_i});
    wire signed [18:0] target_w = mixed_w <<< 1;
    wire silent_w = (phoneme_i == 6'd0 || !powered_i || amplitude_i == 0);
    wire signed [18:0] delta_w = target_w - $signed(lp_r);
    always @(posedge clk_i) begin
        if (!reset_n_i) begin
            div_r <= 0;
            phase_r <= 0;
            lfsr_r <= 16'hACE1;
            lp_r <= 0;
            pcm_o <= 0;
        end else begin
            if (phoneme_start_i) phase_r <= 0;
            if (!powered_i) begin
                phase_r <= 0;
                lp_r <= 0;
                pcm_o <= 0;
            end
            if (div_r == DIV-1) begin
                div_r <= 0;
                if (powered_i) begin
                    if (!phoneme_start_i) phase_r <= phase_r + step_w;
                    lfsr_r <= {lfsr_r[14:0],lfsr_r[15]^lfsr_r[13]^lfsr_r[12]^lfsr_r[10]};
                    if (silent_w) lp_r <= lp_r - (lp_r >>> 2);
                    else lp_r <= lp_r + (delta_w >>> 2);
                    // Conservative diagnostic level; not calibrated against hardware.
                    pcm_o <= silent_w ? 16'sd0 : lp_r[15:0];
                end
            end else div_r <= div_r + 1'b1;
        end
    end
endmodule
