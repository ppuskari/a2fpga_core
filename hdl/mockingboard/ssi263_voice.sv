// Original experimental SSI263 phoneme approximation, FPGA ONLY.
// A 64x128-byte generated timbre bank (not an SSI ROM dump) is played
// through a variable-rate DDS and mixed with dynamic unvoiced consonant hiss.
// The host SSI263 control/CA1 machinery is separate and continues to own
// CPU timing. This module never gates IRQs and needs NO BL616 firmware.
//
// PCM synthesis is intentionally approximate. Real SSI263 articulators are
// switched-capacitor formants whose proprietary parameters are not available.
// Generate hdl/ssi263_voice.mem (from Enhanced Gowin project working dir)
// with: python tools/generate_ssi263_voice.py
module ssi263_voice #(
    parameter integer CLK_HZ = 54_000_000,
    parameter integer SAMPLE_HZ = 16_000
) (
    input  wire               clk_i,
    input  wire               reset_n_i,
    input  wire               powered_i,
    input  wire               phoneme_start_i,
    input  wire [5:0]         phoneme_i,
    input  wire [3:0]         amplitude_i,
    input  wire [7:0]         inflection_i,
    input  wire [7:0]         rate_i,
    output logic signed [15:0] pcm_o
);
    localparam integer SAMPLE_DIV = CLK_HZ / SAMPLE_HZ;
    localparam integer DIV_BITS = $clog2(SAMPLE_DIV);
    logic [DIV_BITS-1:0] divider_r;
    logic [15:0] phase_r;
    logic [15:0] noise_r;
    logic [7:0] sample_byte_r;
    logic [7:0] voice_rom [0:8191];

    // Exactly 8192 original waveform values; 6-bit phoneme + 7-bit index.
    initial $readmemh("hdl/ssi263_voice.mem", voice_rom);
    wire [12:0] voice_addr_w = {phoneme_i, phase_r[15:9]};
    always_ff @(posedge clk_i)
        sample_byte_r <= voice_rom[voice_addr_w];

    wire sample_tick_w = (divider_r == (SAMPLE_DIV - 1));
    // 125Hz nominal 128-sample wavetable; pitch varies with SSI inflection
    // and upper/lower inflection rate bits. Audible approximation only.
    wire [15:0] phase_step_w =
        16'd380 + {8'b0, inflection_i} +
        ({12'b0, rate_i[3:0]} << 3);

    // SSI263 fricatives/noisy consonants: dynamically generated LFSR hiss,
    // not a periodic 16ms loop that produces an audible mechanical buzz.
    function automatic logic noisy_phoneme(input logic [5:0] p);
        case (p)
            6'd39, 6'd40, 6'd41, 6'd42, 6'd43,
            6'd44, 6'd45, 6'd46, 6'd47, 6'd48,
            6'd49, 6'd50, 6'd51, 6'd52, 6'd53,
            6'd54: noisy_phoneme=1'b1;
            default: noisy_phoneme=1'b0;
        endcase
    endfunction

    wire signed [8:0] rom_w = $signed({sample_byte_r[7],sample_byte_r});
    wire signed [8:0] noise_w = $signed({1'b0,noise_r[7:0]}) - 9'sd128;
    wire signed [9:0] source_w =
        noisy_phoneme(phoneme_i) ?
          ($signed({rom_w[8],rom_w}) + ($signed({noise_w[8],noise_w}) >>> 1)) :
           $signed({rom_w[8],rom_w});
    wire signed [14:0] gain_w = source_w * $signed({1'b0,amplitude_i});
    wire signed [15:0] scaled_w = $signed({gain_w[14],gain_w}) <<< 2;

    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            divider_r <= '0;
            phase_r <= 16'd0;
            noise_r <= 16'hACE1;
            pcm_o <= 16'sd0;
        end else begin
            if (phoneme_start_i)
                phase_r <= 16'd0;
            if (!powered_i) begin
                phase_r <= 16'd0;
                pcm_o <= 16'sd0;
            end else if (sample_tick_w) begin
                if (!phoneme_start_i)
                    phase_r <= phase_r + phase_step_w;
                noise_r <= {noise_r[14:0],
                           noise_r[15]^noise_r[13]^noise_r[12]^noise_r[10]};
                // Explicit pause phonemes are silent even with full amplitude.
                if (phoneme_i == 6'd0 || phoneme_i == 6'd63)
                    pcm_o <= 16'sd0;
                else
                    pcm_o <= scaled_w;
            end
            if (sample_tick_w)
                divider_r <= '0;
            else
                divider_r <= divider_r + 1'b1;
        end
    end
endmodule
