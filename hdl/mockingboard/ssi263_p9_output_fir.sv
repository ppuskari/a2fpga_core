// P9 reconstruction: physical switched-capacitor hold -> 4x PCM area
// integration -> 193-tap Hamming FIR -> 44.1 kHz mono PCM.
// Coefficients are re-derived from the MIT Pico SSI263 ssi263.c firwin.
// One multiplier is time-shared over 193 54-MHz cycles for each host
// sample (~1224 cycles), making the filter feasible on Tang Nano 20K.
// Never assume a 193-tap direct combinational FIR.
//
// Fixed-point differences from upstream C: Q15 coefficients,
// logic-clock quantized area integration and a rounded reciprocal of
// the fine-clock interval. These require audio comparison on hardware.
module ssi263_p9_output_fir #(
    parameter integer LOGIC_HZ=54_000_000,
    parameter integer OUTPUT_HZ=44_100
)(
    input wire clk_i,
    input wire reset_n_i,
    input wire powered_i,
    input wire signed [15:0] hold_pcm_i,
    output logic signed [15:0] pcm_o,
    output logic sample_valid_o
);
    localparam integer NTAPS=193;
    localparam integer FINE_HZ=OUTPUT_HZ*4;
    localparam integer AREA_RECIP_Q24=
       ((64'd1<<24)*FINE_HZ+(LOGIC_HZ/2))/LOGIC_HZ;
    logic signed [15:0] taps_rom [0:NTAPS-1];
    logic signed [15:0] fine_ring [0:NTAPS-1];
    initial $readmemh("hdl/ssi263_p9_outfir.mem",taps_rom);

    logic [31:0] phase_r;
    wire [32:0] phase_next_w={1'b0,phase_r}+FINE_HZ;
    wire fine_tick_w=(phase_next_w>=LOGIC_HZ);
    logic signed [31:0] area_acc_r;
    wire signed [31:0] area_sum_w=area_acc_r+$signed(hold_pcm_i);
    wire signed [63:0] area_mul_w=
        $signed(area_sum_w) * $signed(AREA_RECIP_Q24);
    wire signed [31:0] fine_average_w=area_mul_w>>>24;
    wire signed [15:0] fine_pcm_w=
        (fine_average_w>32767) ? 16'sh7fff :
        (fine_average_w< -32768) ? 16'sh8000 :
        fine_average_w[15:0];

    logic [1:0] os_count_r;
    logic [7:0] wr_idx_r,rd_idx_r,tap_idx_r,valid_fine_r;
    logic filtering_r;
    logic signed [47:0] fir_acc_r;
    wire signed [31:0] fir_mult_w =
        $signed(fine_ring[rd_idx_r]) * $signed(taps_rom[tap_idx_r]);
    wire signed [47:0] fir_total_w=
        fir_acc_r + {{16{fir_mult_w[31]}},fir_mult_w};
    wire signed [47:0] fir_result_w=fir_total_w>>>15;

    always_ff @(posedge clk_i) begin
        if(!reset_n_i || !powered_i) begin
            phase_r<=0;area_acc_r<=0;
            os_count_r<=0;wr_idx_r<=0;rd_idx_r<=0;
            tap_idx_r<=0;valid_fine_r<=0;filtering_r<=0;
            fir_acc_r<=0;pcm_o<=0;sample_valid_o<=0;
        end else begin
            sample_valid_o<=0;
            if(fine_tick_w) begin
                phase_r<=phase_next_w-LOGIC_HZ;
                area_acc_r<=0;
                fine_ring[wr_idx_r]<=fine_pcm_w;
                if(wr_idx_r==NTAPS-1)wr_idx_r<=0;
                else wr_idx_r<=wr_idx_r+1'b1;
                if(valid_fine_r<NTAPS)valid_fine_r<=valid_fine_r+1'b1;
                if(os_count_r==2'd3) begin
                    os_count_r<=0;
                    if(!filtering_r && valid_fine_r>=NTAPS-1) begin
                       filtering_r<=1;
                       fir_acc_r<=0;tap_idx_r<=0;
                       rd_idx_r<=wr_idx_r;
                    end
                end else os_count_r<=os_count_r+1'b1;
            end else begin
                phase_r<=phase_next_w[31:0];
                area_acc_r<=area_sum_w;
            end
            if(filtering_r) begin
                fir_acc_r<=fir_total_w;
                if(rd_idx_r==0)rd_idx_r<=NTAPS-1;
                else rd_idx_r<=rd_idx_r-1'b1;
                if(tap_idx_r==NTAPS-1) begin
                    filtering_r<=0;
                    pcm_o<= (fir_result_w>32767) ? 16'sh7fff :
                            (fir_result_w< -32768) ? 16'sh8000 :
                            fir_result_w[15:0];
                    sample_valid_o<=1;
                end else tap_idx_r<=tap_idx_r+1'b1;
            end
        end
    end
endmodule
