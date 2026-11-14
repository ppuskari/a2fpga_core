// M6.4.2 diagnostic only: quiet post-limiter right-channel PCM pilot.
// An uninterrupted ~1 kHz pilot in an HDMI capture proves the HDMI audio
// transport is alive even if the upstream Ensoniq music disappears.
// Disabled synthesis generates direct wires; no clocks/PLLs are modified.
module mb_hdmi_audio_pilot #(
    parameter bit ENABLE = 1'b0,
    parameter int HALF_PERIOD_SAMPLES = 22,
    parameter logic signed [15:0] AMPLITUDE = 16'sd256,
    parameter logic signed [15:0] CEILING = 16'sd26028
) (
    input logic clk_pixel_i,
    input logic reset_n_i,
    input logic sample_tick_i,   // one-cycle 44.1 kHz pulse from audio_timing
    input logic signed [15:0] left_pcm_i,
    input logic signed [15:0] right_pcm_i,
    output wire signed [15:0] left_pcm_o,
    output wire signed [15:0] right_pcm_o
);
    assign left_pcm_o = left_pcm_i;
    generate if (ENABLE) begin : gen_pilot
        localparam int COUNTER_W = (HALF_PERIOD_SAMPLES < 2) ?
            1 : $clog2(HALF_PERIOD_SAMPLES);
        logic [COUNTER_W-1:0] half_counter_r;
        logic polarity_r;

        always_ff @(posedge clk_pixel_i) begin
            if (!reset_n_i) begin
                half_counter_r <= '0;
                polarity_r <= 1'b0;
            end else if (sample_tick_i) begin
                if (half_counter_r == COUNTER_W'(HALF_PERIOD_SAMPLES-1)) begin
                    half_counter_r <= '0;
                    polarity_r <= ~polarity_r;
                end else
                    half_counter_r <= half_counter_r + 1'b1;
            end
        end

        wire signed [16:0] pilot_w =
            polarity_r ? $signed({AMPLITUDE[15], AMPLITUDE}) :
                         -$signed({AMPLITUDE[15], AMPLITUDE});
        wire signed [16:0] sum_w =
            $signed({right_pcm_i[15],right_pcm_i}) + pilot_w;
        assign right_pcm_o =
            (sum_w > $signed({CEILING[15],CEILING})) ? CEILING :
            (sum_w < -$signed({CEILING[15],CEILING})) ? -CEILING :
            sum_w[15:0];
    end else begin : gen_passthrough
        assign right_pcm_o = right_pcm_i;
    end endgenerate
endmodule
