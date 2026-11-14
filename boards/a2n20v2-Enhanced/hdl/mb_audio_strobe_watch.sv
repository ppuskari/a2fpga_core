// M6.4.5a diagnosis: does the 44.1kHz sample strobe stop?
// No audio signals are altered.  An LED captures missed sample ticks.
module mb_audio_strobe_watch #(
    parameter integer TIMEOUT_CYCLES = 54000, // 2ms at 27MHz
    parameter integer HEARTBEAT_SAMPLES = 22050
)(
    input wire clk_pixel_i,
    input wire reset_n_i,
    input wire sample_tick_i,
    input wire clear_i,
    output reg stalled_o,
    output reg heartbeat_o
);
    localparam integer CW = (TIMEOUT_CYCLES < 2) ? 1 : $clog2(TIMEOUT_CYCLES+1);
    localparam integer HW = (HEARTBEAT_SAMPLES < 2) ? 1 : $clog2(HEARTBEAT_SAMPLES);
    reg [CW-1:0] since_tick_r;
    reg [HW-1:0] heartbeat_count_r;
    always @(posedge clk_pixel_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            since_tick_r <= '0;
            heartbeat_count_r <= '0;
            heartbeat_o <= 1'b0;
            stalled_o <= 1'b0;
        end else begin
            if (clear_i)
                stalled_o <= 1'b0;
            if (sample_tick_i) begin
                since_tick_r <= '0;
                if (heartbeat_count_r == HW'(HEARTBEAT_SAMPLES-1)) begin
                    heartbeat_count_r <= '0;
                    heartbeat_o <= ~heartbeat_o;
                end else heartbeat_count_r <= heartbeat_count_r + 1'b1;
            end else if (since_tick_r < CW'(TIMEOUT_CYCLES)) begin
                since_tick_r <= since_tick_r + 1'b1;
            end else begin
                stalled_o <= 1'b1;
            end
        end
    end
endmodule
