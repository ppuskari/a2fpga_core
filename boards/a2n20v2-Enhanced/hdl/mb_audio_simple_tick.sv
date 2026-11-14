// M6.4.5d: alternate minimal 44.1kHz pixel-domain sample strobe.
// No derived clocks, only a one-cycle enable; expected 612/613 pixel
// cycles between pulses at 27MHz. The PCM, HDMI and DOC engines stay.
module mb_audio_simple_tick #(
    parameter integer CLK_RATE=27000000,
    parameter integer AUDIO_RATE=44100
)(
    input wire clk_i,
    input wire reset_i,
    output reg audio_tick_o
);
    reg [31:0] accumulator_r = 32'd0;
    wire [32:0] sum_w = {1'b0,accumulator_r} + 33'(AUDIO_RATE);
    always @(posedge clk_i or posedge reset_i) begin
        if (reset_i) begin
            accumulator_r <= 32'd0;
            audio_tick_o <= 1'b0;
        end else begin
            audio_tick_o <= 1'b0;
            if (sum_w >= 33'(CLK_RATE)) begin
                accumulator_r <= sum_w[31:0] - 32'(CLK_RATE);
                audio_tick_o <= 1'b1;
            end else accumulator_r <= sum_w[31:0];
        end
    end
endmodule
