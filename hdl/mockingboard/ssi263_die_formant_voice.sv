// P7 R1: independent fixed-point SSI-263 voice-rendering experiment.
// Apple II SSI registers, phoneme-duration timer and VIA CA1 remain in
// ssi263_control/ssi263_slot; this module ONLY generates audio.
// Die-decoded 64x29-bit phoneme parameters: Tamas Geczy's MIT SSI263
// research (see P7 documentation). This is NOT a cycle-accurate model.
// Three parallel damped IIR formant sections, pulse/glottal excitation,
// shaped LFSR frication, basic stop closures and decaying silence.
// No MAME/GPL glottal samples and no BL616 firmware dependency.
module ssi263_die_formant_voice #(
    parameter integer CLK_HZ = 54_000_000,
    parameter integer SAMPLE_HZ = 16_000
) (
    input wire clk_i,
    input wire reset_n_i,
    input wire powered_i,
    input wire phoneme_start_i,
    input wire [5:0] phoneme_i,
    input wire [3:0] amplitude_i,
    input wire [7:0] inflection_i,
    input wire [7:0] rate_i,
    output logic signed [15:0] pcm_o
);
    localparam integer SAMPLE_DIV = CLK_HZ / SAMPLE_HZ;
    localparam integer DIV_BITS = $clog2(SAMPLE_DIV);
    logic [DIV_BITS-1:0] divider_r;
    wire sample_tick_w = (divider_r == SAMPLE_DIV-1);
    logic [15:0] phase_r;
    logic [15:0] lfsr_r;
    logic signed [23:0] f1_y1_r, f1_y2_r;
    logic signed [23:0] f2_y1_r, f2_y2_r;
    logic signed [23:0] f3_y1_r, f3_y2_r;
    logic [7:0] phoneme_age_r;

    // Each 128-bit entry: c1 c2 c3 d1 d2 d3 metadata32.
    // c=2*r*cos(2*pi*f/fs), d=r*r (Q14). F1/F2/F3 come from
    // the 4-bit decoded real SSI-263 phoneme capacitor settings.
    logic [127:0] die_coeff_rom [0:63];
    initial $readmemh("hdl/ssi263_die_formants.mem", die_coeff_rom);
    wire [127:0] rom_w = die_coeff_rom[phoneme_i];
    wire signed [15:0] c1_w = rom_w[127:112];
    wire signed [15:0] c2_w = rom_w[111:96];
    wire signed [15:0] c3_w = rom_w[95:80];
    wire signed [15:0] d1_w = rom_w[79:64];
    wire signed [15:0] d2_w = rom_w[63:48];
    wire signed [15:0] d3_w = rom_w[47:32];
    wire [3:0] va_w = rom_w[31:28]; // voiced amplitude
    wire [3:0] fa_w = rom_w[27:24]; // frication amplitude
    wire closure_clear_w = rom_w[23]; // b00=0: stop/closure
    wire [3:0] nas_w = rom_w[19:16];

    function automatic signed [23:0] resonator(
        input signed [15:0] c,
        input signed [15:0] d,
        input signed [23:0] y1,
        input signed [23:0] y2,
        input signed [15:0] excite
    );
        reg signed [47:0] accum;
        begin
            accum = (($signed(c) * $signed(y1) -
                      $signed(d) * $signed(y2)) >>> 14) +
                    $signed(excite);
            // State saturation prevents wrapped IIR feedback under shocks.
            if (accum > 48'sd8388607)
                resonator = 24'sh7fffff;
            else if (accum < -48'sd8388608)
                resonator = 24'sh800000;
            else
                resonator = accum[23:0];
        end
    endfunction

    function automatic signed [15:0] clip16(input signed [31:0] v);
        begin
            if (v > 32'sd32767) clip16 = 16'sh7fff;
            else if (v < -32'sd32768) clip16 = 16'sh8000;
            else clip16 = v[15:0];
        end
    endfunction

    // 125-ish Hz base pitch, varied by original SSI inflection/rate fields.
    wire [15:0] phase_step_w =
        16'd400 + {8'd0,inflection_i} + ({12'd0,rate_i[3:0]} << 3);
    wire [16:0] phase_sum_w = {1'b0,phase_r} + {1'b0,phase_step_w};
    wire signed [15:0] glottal_w =
        phase_sum_w[16] ? 16'sd320 :
        (phase_r[15:12] == 4'd0 ? 16'sd52 :
         (phase_r[15:12] == 4'd1 ? -16'sd32 : 16'sd0));
    wire signed [15:0] noise_raw_w =
        $signed({8'd0,lfsr_r[7:0]}) - 16'sd128;
    wire signed [15:0] highpass_noise_w =
        noise_raw_w - ($signed({8'd0,lfsr_r[15:8]}) - 16'sd128);
    wire pause_w = (phoneme_i == 6'd0 || phoneme_i == 6'd63);
    // The decoded b00 zero identifies a stop; keep most of the closure
    // quiet but provide a short release/noise burst in the opening window.
    wire stop_hold_w = !closure_clear_w &&
                       (phoneme_age_r < 8'd12);
    wire signed [31:0] voiced_product_w =
        $signed(glottal_w) * $signed({1'b0,va_w}) *
        $signed({1'b0,amplitude_i});
    wire signed [31:0] noise_product_w =
        $signed(highpass_noise_w) * $signed({1'b0,fa_w}) *
        $signed({1'b0,amplitude_i});
    wire signed [15:0] voiced_w =
        (pause_w || !closure_clear_w) ? 16'sd0 :
        clip16(voiced_product_w >>> 7);
    wire signed [15:0] fricative_w =
        (pause_w || stop_hold_w) ? 16'sd0 :
        clip16(noise_product_w >>> 6);
    // NAS lowers voiced oral energy, permitting the nasal body to remain.
    wire signed [15:0] voiced_nas_w =
        (nas_w != 4'd0) ? (voiced_w >>> 1) : voiced_w;
    wire signed [15:0] drive1_w = voiced_nas_w;
    wire signed [15:0] drive2_w =
        clip16(($signed(voiced_nas_w) >>> 2) + $signed(fricative_w));
    wire signed [15:0] drive3_w =
        clip16(($signed(voiced_nas_w) >>> 3) +
               ($signed(fricative_w) >>> 1));
    wire signed [23:0] f1_next_w =
        resonator(c1_w,d1_w,f1_y1_r,f1_y2_r,drive1_w);
    wire signed [23:0] f2_next_w =
        resonator(c2_w,d2_w,f2_y1_r,f2_y2_r,drive2_w);
    wire signed [23:0] f3_next_w =
        resonator(c3_w,d3_w,f3_y1_r,f3_y2_r,drive3_w);
    // Reduced output contributions leave headroom for P6 speech gain.
    wire signed [31:0] combined_w =
        ($signed(f1_next_w) >>> 2) +
        ($signed(f2_next_w) >>> 2) +
        ($signed(f3_next_w) >>> 2);
    wire signed [15:0] limited_w = clip16(combined_w);
    wire signed [31:0] smooth_delta_w = $signed(limited_w)-$signed(pcm_o);
    wire signed [31:0] smooth_step_w =
        (smooth_delta_w >>> 2) == 0 && smooth_delta_w != 0 ?
        (smooth_delta_w > 0 ? 32'sd1 : -32'sd1) :
        (smooth_delta_w >>> 2);
    wire signed [15:0] smooth_next_w =
        clip16($signed(pcm_o)+smooth_step_w);

    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            divider_r <= '0;
            phase_r <= 16'd0;
            lfsr_r <= 16'hACE1;
            phoneme_age_r <= 8'd0;
            f1_y1_r <= 24'sd0; f1_y2_r <= 24'sd0;
            f2_y1_r <= 24'sd0; f2_y2_r <= 24'sd0;
            f3_y1_r <= 24'sd0; f3_y2_r <= 24'sd0;
            pcm_o <= 16'sd0;
        end else begin
            if (sample_tick_w)
                divider_r <= '0;
            else
                divider_r <= divider_r + 1'b1;
            if (phoneme_start_i)
                phoneme_age_r <= 8'd0;
            if (!powered_i) begin
                phase_r <= 16'd0;
                phoneme_age_r <= 8'd0;
                f1_y1_r <= 24'sd0; f1_y2_r <= 24'sd0;
                f2_y1_r <= 24'sd0; f2_y2_r <= 24'sd0;
                f3_y1_r <= 24'sd0; f3_y2_r <= 24'sd0;
                pcm_o <= 16'sd0;
            end else if (sample_tick_w) begin
                phase_r <= phase_sum_w[15:0];
                lfsr_r <= {lfsr_r[14:0],
                    lfsr_r[15]^lfsr_r[13]^lfsr_r[12]^lfsr_r[10]};
                if (!phoneme_start_i && phoneme_age_r != 8'hff)
                    phoneme_age_r <= phoneme_age_r + 1'b1;
                f1_y2_r <= f1_y1_r; f1_y1_r <= f1_next_w;
                f2_y2_r <= f2_y1_r; f2_y1_r <= f2_next_w;
                f3_y2_r <= f3_y1_r; f3_y1_r <= f3_next_w;
                pcm_o <= smooth_next_w;
            end
        end
    end
endmodule
