// M3 experimental HDMI output meter, observational only.
// Pixel-clock domain: unsigned sample-peak detector (L/R) over 44100 frames,
// one snapshot per second; no multiply, division, DSP block or PCM changes.
// Logic-clock domain: toggle-qualified bundled-data CDC, with a full clock
// of settling after the two-flop toggle synchronizer before data is latched.
// Snapshots are held stable for ~1 second at source, long enough to settle.
// Intended for low-rate MCU diagnostics, NOT an audio-rate level detector.
module hdmi_mix_meter #(
    parameter integer SAMPLE_RATE = 44100
) (
    input  wire clk_pixel_i,
    input  wire clk_logic_i,
    input  wire reset_n_i,
    input  wire sample_tick_i,
    input  wire signed [15:0] sample_l_i,
    input  wire signed [15:0] sample_r_i,
    input  wire [7:0] clip_history_i,
    output reg  [15:0] peak_l_o,
    output reg  [15:0] peak_r_o,
    output reg  [7:0] clip_history_o,
    output reg  valid_o
);
    localparam integer COUNT_WIDTH = $clog2(SAMPLE_RATE + 1);
    reg [COUNT_WIDTH-1:0] frame_count_r;
    reg [15:0] window_peak_l_r, window_peak_r_r;
    reg [39:0] snapshot_pixel_r;
    reg snapshot_toggle_pixel_r;

    // Absolute value is unsigned: -32768 maps correctly to 32768.
    wire [15:0] abs_l_w = sample_l_i[15] ?
        (~sample_l_i + 16'd1) : sample_l_i;
    wire [15:0] abs_r_w = sample_r_i[15] ?
        (~sample_r_i + 16'd1) : sample_r_i;
    wire [15:0] max_l_w =
        (abs_l_w > window_peak_l_r) ? abs_l_w : window_peak_l_r;
    wire [15:0] max_r_w =
        (abs_r_w > window_peak_r_r) ? abs_r_w : window_peak_r_r;

    always @(posedge clk_pixel_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            frame_count_r <= 0;
            window_peak_l_r <= 0;
            window_peak_r_r <= 0;
            snapshot_pixel_r <= 0;
            snapshot_toggle_pixel_r <= 0;
        end else if (sample_tick_i) begin
            if (frame_count_r == SAMPLE_RATE - 1) begin
                frame_count_r <= 0;
                window_peak_l_r <= 0;
                window_peak_r_r <= 0;
                snapshot_pixel_r <= {clip_history_i, max_l_w, max_r_w};
                snapshot_toggle_pixel_r <= ~snapshot_toggle_pixel_r;
            end else begin
                frame_count_r <= frame_count_r + 1'b1;
                window_peak_l_r <= max_l_w;
                window_peak_r_r <= max_r_w;
            end
        end
    end

    // Two-flop toggle synchronization. The multibit data bundle stays static
    // until the next 1-second snapshot; register it a clock later, never
    // sample a crossing audio bus while it is being updated.
    reg [1:0] toggle_sync_r;
    reg seen_toggle_r, capture_pending_r;
    always @(posedge clk_logic_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            toggle_sync_r <= 0;
            seen_toggle_r <= 0;
            capture_pending_r <= 0;
            peak_l_o <= 0;
            peak_r_o <= 0;
            clip_history_o <= 0;
            valid_o <= 0;
        end else begin
            toggle_sync_r <= {toggle_sync_r[0], snapshot_toggle_pixel_r};
            if (toggle_sync_r[1] != seen_toggle_r) begin
                seen_toggle_r <= toggle_sync_r[1];
                capture_pending_r <= 1'b1;
            end else if (capture_pending_r) begin
                {clip_history_o, peak_l_o, peak_r_o} <= snapshot_pixel_r;
                valid_o <= 1'b1;
                capture_pending_r <= 1'b0;
            end
        end
    end
endmodule
