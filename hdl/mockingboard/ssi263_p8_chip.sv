// SSI-263 P8 full-chip RTL architecture (bring-up / reference equivalence target).
// Copyright (c) 2026, project contributors. MIT reference data and math from
// Tamas Geczy ssi263-speech, pinned under reference/ssi263/pico-v1.0.1.
// IMPORTANT: not yet silicon-equivalent; DO NOT promote over P6 or enable in
// hardware until trace, spectrum, timing and resource acceptance gates pass.
//
// Unlike P7, this module owns ALL SSI-263 registers R0..R4, A/R, both clocks,
// the die ROM, 6 transitioning fields, a filtered glottal/noise excitation,
// five serial vocal-tract stages, and the output. No old ssi263_voice inside.
module ssi263_p8_chip #(
    parameter integer LOGIC_HZ = 54_000_000,
    parameter integer OUTPUT_HZ = 44_100,
    parameter integer FRAME_XCK = 4096,
    // DSP diagnostic controls: enable/disable inputs to isolate hiss.
    parameter bit EXCITATION_VOICE_ENABLE = 1'b1,
    parameter bit EXCITATION_NOISE_ENABLE = 1'b1,
    // Output calibration is performed at the chip boundary, not in the
    // shared HDMI mixer. 6x avoids the clipping seen with 9x while
    // approaching the native recording's ~-3 dBFS peak.
    // This does NOT imply waveform fidelity to the reference C engine.
    parameter integer OUTPUT_GAIN_NUM = 6
)(
    input wire clk_i,
    input wire reset_n_i,
    input wire xck_tick_i,
    input wire write_i,
    input wire [2:0] reg_i,
    input wire [7:0] data_i,
    output wire ar_n_o,
    output wire powered_o,
    output wire [5:0] phoneme_o,
    output wire [7:0] r3_debug_o,
    output logic signed [15:0] pcm_o
);
    logic [7:0] r0,r1,r2,r3,r4;
    logic [1:0] mode_r;
    logic mode_valid_r;
    logic request_r;
    logic [19:0] duration_xck_r, remain_xck_r;
    logic [15:0] frame_xck_r;
    logic [15:0] filter_xck_r;
    logic [9:0] fc_div_r;
    logic fc_start_r;
    logic [15:0] pitch_xck_r;
    logic [15:0] pitch_div_r;
    logic pulse_pending_r;
    logic [5:0] glottal_age_r;
    // Full 36-filter-tick glottal impulse response from pinned Pico C.
    logic signed [15:0] glottal_rom[0:63];
    initial $readmemh("hdl/ssi263_p8_glottal.mem",glottal_rom);
    logic [15:0] lfsr_r;
    logic signed [15:0] noise_prev_r;
    // Symmetric finite-impulse-response output anti-image filter.
    // Unlike P8's direct asynchronous held-sample capture, the 44.1 kHz
    // 5-tap [1 4 6 4 1]/16 FIR attenuates switched-capacitor images.
    logic signed [15:0] fir0_r,fir1_r,fir2_r,fir3_r;
    localparam integer OUTPUT_DIV=LOGIC_HZ/OUTPUT_HZ;
    localparam integer OUTCW=$clog2(OUTPUT_DIV);
    logic [OUTCW-1:0] out_count_r;
    logic signed [15:0] held_pcm_r;
    logic signed [31:0] hp_x_r,hp_y_r;
    wire signed [63:0] hp_fb_w = ($signed(hp_y_r) * 64'sd32100) >>> 15;
    wire signed [63:0] hp_acc_w =
        $signed(next_filter_w) - $signed(hp_x_r) + hp_fb_w;
    wire signed [31:0] hp_next_w = clip32(hp_acc_w);
    wire signed [63:0] fir_sum_w =
        $signed(held_pcm_r) + ($signed(fir0_r) <<< 2) +
        ($signed(fir1_r) * 64'sd6) + ($signed(fir2_r) <<< 2) +
        $signed(fir3_r);
    logic [2:0] stage_r;
    logic signed [31:0] tract_r;
    logic signed [31:0] tract_y1_r[0:4],tract_y2_r[0:4];
    logic signed [31:0] tract_x1_r[0:4],tract_x2_r[0:4];
    logic [15:0] field_r[0:5];  // 4-bit code plus 12 fractional bits
    logic [3:0] target_r[0:5];
    logic [15:0] amp_r; // Q12, 0..15; physical VOL glides per phoneme
    // SSI R1 pitch transition kept at Q12 for fractional control steps.
    logic [23:0] pitch_glide_r;
    logic [23:0] pitch_target_r;
    logic [15:0] elapsed_fc_r;
    logic [15:0] frame_fc_r;
    logic [7:0] closure_level_r;
    logic closing_r, release_allowed_r, release_open_r;
    logic [19:0] elapsed_xck_r;
    logic [19:0] close_delay_xck_r, release_window_xck_r;
    logic [15:0] noise_f2_gain_r, noise_f5_gain_r;
    // Pinned Pico default: 2-pole band-pass at .28*fc, BW .15*fc;
    // Q14: a1=-3833, a2=6384, peak-normalized g=5005.
    logic signed [31:0] ns_x1_r,ns_x2_r,ns_y1_r,ns_y2_r;
    wire signed [15:0] noise_bit_w = lfsr_r[14] ? 16'sd32767 : -16'sd32767;
    wire signed [63:0] ns_sum_w =
       (64'sd5005 * ($signed(noise_bit_w)-$signed(ns_x2_r)) -
        64'sd3833 * $signed(ns_y1_r) -
        64'sd6384 * $signed(ns_y2_r)) >>> 14;
    wire signed [31:0] ns_next_w = clip32(ns_sum_w);

    logic [31:0] die_rom[0:63];
    logic [55:0] coefficient_rom[0:49];
    initial begin
       $readmemh("hdl/ssi263_p8_params.mem",die_rom);
       $readmemh("hdl/ssi263_p8_coefs.mem",coefficient_rom);
    end
    wire [31:0] die_w=die_rom[r0[5:0]];
    wire [3:0] f1_target_w=die_w[31:28];
    wire [3:0] f2_target_w=die_w[27:24];
    wire [3:0] f3_target_w=die_w[23:20];
    wire [3:0] nas_target_w=die_w[19:16];
    wire [3:0] va_target_w=die_w[15:12];
    wire [3:0] fa_target_w=die_w[11:8];
    wire closure_clear_w=die_w[2];
    wire release_allowed_w=die_w[1];
    wire route_f2_w=die_w[0];
    assign ar_n_o=~request_r;
    assign powered_o=mode_valid_r && !r3[7];
    assign phoneme_o=r0[5:0];
    assign r3_debug_o=r3;

    function automatic [19:0] duration_ticks(
       input [7:0] ph, input [7:0] rate, input [1:0] md
    );
       reg [19:0] frame;
       begin
          frame=FRAME_XCK * (20'd16-{16'd0,rate[7:4]});
          duration_ticks=frame * ((md==2'd1) ? 20'd1 :
                                 (20'd4-{18'd0,ph[7:6]}));
       end
    endfunction
    function automatic signed [31:0] clip32(input signed [63:0] v);
       begin
          if(v>64'sd2147483647) clip32=32'sh7fffffff;
          else if(v< -64'sd2147483648) clip32=32'sh80000000;
          else clip32=v[31:0];
       end
    endfunction
    function automatic signed [15:0] clip16(input signed [63:0] v);
       begin
          if(v>64'sd32767) clip16=16'sh7fff;
          else if(v< -64'sd32768) clip16=16'sh8000;
          else clip16=v[15:0];
       end
    endfunction
    function automatic [11:0] approach(
       input [11:0] value, input [11:0] dest,input [11:0] step
    );
       begin
          if(value<dest) approach=(dest-value<=step) ? dest : value+step;
          else if(value>dest) approach=(value-dest<=step) ? dest : value-step;
          else approach=value;
       end
    endfunction

    // Derive filter clock from R4 exactly as the chip reference:
    // fc = XCK / (2*(256-FF)).  R4 is NOT ignored as in P7.
    wire [9:0] filter_period_w=(10'd256-{2'd0,r4})<<1;
    // Phoneme length is measured on the independent XCK clock.
    wire [19:0] frame_now_w=FRAME_XCK*(20'd16-{16'd0,r2[7:4]});
    wire [11:0] imm_pitch_w={r2[3],8'b0,r2[2:0]};
    wire [11:0] combined_pitch_w=pitch_glide_r[23:12]+imm_pitch_w;
    wire [15:0] desired_pitch_w=(16'd4096-combined_pitch_w)<<3;
    wire [11:0] desired_pitch_target_w=
        (mode_r==2'd3) ? {r1[7:3],6'b0} : {r1,3'b0};
    // Exact reference law per filter tick (Q12):
    // step = art_codes_per_frame[ART] * (2*(256-FF)) /
    //        (4096*(16-RATE)); VA/FA use the 6x amp multiplier.
    // F1 alone uses the 2.25x field-speed factor from the pinned model.
    // Use a small 16-entry 1/(16-RATE) table, no runtime divider.
    function automatic [12:0] rate_inv_q12(input [3:0] rate);
      case (rate)
        4'd0: rate_inv_q12=13'd256;
        4'd1: rate_inv_q12=13'd273;
        4'd2: rate_inv_q12=13'd293;
        4'd3: rate_inv_q12=13'd315;
        4'd4: rate_inv_q12=13'd341;
        4'd5: rate_inv_q12=13'd372;
        4'd6: rate_inv_q12=13'd410;
        4'd7: rate_inv_q12=13'd455;
        4'd8: rate_inv_q12=13'd512;
        4'd9: rate_inv_q12=13'd585;
        4'd10:rate_inv_q12=13'd683;
        4'd11:rate_inv_q12=13'd819;
        4'd12:rate_inv_q12=13'd1024;
        4'd13:rate_inv_q12=13'd1365;
        4'd14:rate_inv_q12=13'd2048;
        default:rate_inv_q12=13'd4096;
      endcase
    endfunction
    function automatic [14:0] art_rate_q12(input [2:0] a);
      case (a)
        3'd0:art_rate_q12=15'd5734;
        3'd1:art_rate_q12=15'd7373;
        3'd2:art_rate_q12=15'd9421;
        3'd3:art_rate_q12=15'd11878;
        3'd4:art_rate_q12=15'd13926;
        3'd5:art_rate_q12=15'd16384;
        3'd6:art_rate_q12=15'd18842;
        default:art_rate_q12=15'd20890;
      endcase
    endfunction
    wire [63:0] step_product_w =
       $unsigned(art_rate_q12(r3[6:4])) *
       $unsigned(filter_period_w) *
       $unsigned(rate_inv_q12(r2[7:4]));
    wire [15:0] slow_step_w = (step_product_w + 64'd8388608) >> 24;
    wire [15:0] f1_step_w = (slow_step_w * 16'd9) >> 2;
    wire [15:0] fast_step_w = slow_step_w * 16'd6;
    wire [2:0] duration_frames_w = (mode_r==2'd1) ? 3'd1 :
                                  (3'd4 - {1'b0,r0[7:6]});
    wire [63:0] amp_step_product_w =
       64'd61440 * $unsigned(filter_period_w) *
       $unsigned(rate_inv_q12(r2[7:4]));
    wire [15:0] amp_step_base_w =
       (amp_step_product_w + 64'd8388608) >> 24;
    wire [15:0] amp_step_w =
       (duration_frames_w == 3'd1) ? amp_step_base_w :
       (duration_frames_w == 3'd2) ? (amp_step_base_w >> 1) :
       (duration_frames_w == 3'd3) ?
          (($unsigned({16'd0,amp_step_base_w}) * 32'd21845) >> 16) :
       (amp_step_base_w >> 2);
    // R1 glide code table from pinned SSI263 params (Q12):
    // modes 1/2 are immediate; mode 3 applies step/FC tick.
    function automatic [13:0] glide_mult_q12(input [2:0] code);
      case (code)
        3'd0:glide_mult_q12=14'd4096;
        3'd1:glide_mult_q12=14'd3940;
        3'd2:glide_mult_q12=14'd5022;
        3'd3:glide_mult_q12=14'd10084;
        3'd4:glide_mult_q12=14'd8569;
        default:glide_mult_q12=14'd10084;
      endcase
    endfunction
    wire [63:0] glide_product_w =
       $unsigned(glide_mult_q12(r1[2:0])) *
       $unsigned(filter_period_w) *
       $unsigned(rate_inv_q12(r2[7:4])) * 64'd32;
    wire [23:0] glide_step_w=(glide_product_w+64'd8388608)>>24;
    function automatic [23:0] approach24(
      input [23:0] value,input [23:0] dest,input [23:0] step
    );
      begin
        if(value<dest)
           approach24=(dest-value<=step)?dest:value+step;
        else if(value>dest)
           approach24=(value-dest<=step)?dest:value-step;
        else approach24=value;
      end
    endfunction
    function automatic [15:0] approach16(
       input [15:0] value,input [15:0] dest,input [15:0] step
    );
      begin
        if(value<dest)
            approach16=(dest-value<=step)?dest:value+step;
        else if(value>dest)
            approach16=(value-dest<=step)?dest:value-step;
        else
            approach16=value;
      end
    endfunction

    // One shared section-processing slot, five passes per filter sample.
    // Avoid a five-biquad combinational DSP cascade on the 54 MHz path.
    wire [5:0] coeff_index_w =
        (stage_r==3'd1) ? {2'b00,field_r[0][15:12]} :
        (stage_r==3'd2) ? {2'b01,field_r[1][15:12]} :
        (stage_r==3'd3) ? {2'b10,field_r[2][15:12]} :
        (stage_r==3'd4) ? 6'd48 : 6'd49;
    wire [55:0] coeff_w=coefficient_rom[coeff_index_w];
    wire signed [15:0] a1_w=coeff_w[55:40];
    wire signed [15:0] a2_w=coeff_w[39:24];
    wire signed [24:0] gain_w={1'b0,coeff_w[23:0]};
    // In the reference the b02 route chooses *both* F2 and F5
    // injection levels: b02=0 -> (F2=0,F5=1), b02=1 ->
    // (F2=1,F5=.25). The P8 either/or selector was wrong.
    wire signed [31:0] injected_f2_w=clip32(
        $signed(tract_r)+ (($signed(noise_source_w) *
        $signed({1'b0,noise_f2_gain_r})) >>> 12));
    wire signed [31:0] injected_f5_w=clip32(
        $signed(tract_r)+ (($signed(noise_source_w) *
        $signed({1'b0,noise_f5_gain_r})) >>> 12));
    wire signed [31:0] drive_w =
        (stage_r==3'd2) ? injected_f2_w :
        (stage_r==3'd5) ? injected_f5_w : tract_r;
    wire signed [63:0] bilinear_input_w=
        $signed(drive_w)+($signed(tract_x1_r[stage_r-1])<<<1)+
        $signed(tract_x2_r[stage_r-1]);
    wire signed [63:0] filter_sum_w=
        (($signed(gain_w)*bilinear_input_w) >>> 24)+
        (($signed(a1_w)*$signed(tract_y1_r[stage_r-1]))>>>14)-
        (($signed(a2_w)*$signed(tract_y2_r[stage_r-1]))>>>14);
    wire signed [31:0] next_filter_w=clip32(filter_sum_w);
    wire signed [15:0] noise_now_w=
        $signed({8'b0,lfsr_r[7:0]})-16'sd128;
    wire signed [15:0] shaped_noise_w=noise_now_w-noise_prev_r;
    wire signed [15:0] glottal_w=glottal_rom[glottal_age_r];
    wire [15:0] amplitude_w={12'd0,amp_r[15:12]};
    // Both VA and R3 amplitude are encoded 0..15. Normalize by
    // 15*15=225, not 4096: the old >>>12 discarded ~25 dB and
    // forced a near-silent glottal excitation into the resonators.
    wire signed [31:0] voice_source_w=EXCITATION_VOICE_ENABLE ?
        (($signed(glottal_w)*$signed({1'b0,field_r[4][15:12]})*
        $signed({1'b0,amplitude_w})) / 32'sd225) : 32'sd0;
    // First-order noise excitation remains distinct from the
    // missing calibrated band-pass. 0.012 * 32768 ~ 393 Q15.
    // Source equivalent in the C model: nz=noise*0.012/15,
    // subsequently scaled by the per-path FA transition and VOL.
    // In Q15 this is 393/15 before the F2/F5 injection gains.
    wire signed [63:0] noise_product_w =
        $signed(ns_next_w) * 64'sd393 *
        $signed({1'b0,amplitude_w});
    wire signed [31:0] noise_source_w=EXCITATION_NOISE_ENABLE ?
        clip32(noise_product_w / 64'sd491520) : 32'sd0;
    wire [15:0] noise_f2_target_w =
        (!closing_r || release_open_r) && route_f2_w ?
        field_r[5] : 16'd0;
    wire [15:0] noise_f5_target_w =
        (!closing_r || release_open_r) ?
        (route_f2_w ? (field_r[5]>>2) : field_r[5]) : 16'd0;
    wire signed [31:0] start_drive_w=
        (!powered_o || r0[5:0]==6'd0 || r0[5:0]==6'd63 ||
         (!closure_clear_w && closure_level_r==0)) ? 32'sd0 :
        voice_source_w;

    integer i;
    always_ff @(posedge clk_i) begin
       if (!reset_n_i) begin
          r0<=0; r1<=0; r2<=0; r3<=8'h80; r4<=0;
          mode_r<=0; mode_valid_r<=0; request_r<=0;
          duration_xck_r<=0; remain_xck_r<=0;
          frame_xck_r<=0; filter_xck_r<=0;
          fc_div_r<=0; fc_start_r<=0;
          pitch_xck_r<=0; pitch_div_r<=0; pulse_pending_r<=0;
          glottal_age_r<=6'd63; lfsr_r<=16'hace1;
          noise_prev_r<=0;
          out_count_r<=0; held_pcm_r<=0; pcm_o<=0;
          fir0_r<=0;fir1_r<=0;fir2_r<=0;fir3_r<=0;
          hp_x_r<=0; hp_y_r<=0;
          stage_r<=0; tract_r<=0;
          amp_r<=0; pitch_glide_r<=0; pitch_target_r<=0;
          elapsed_fc_r<=0; frame_fc_r<=0; closure_level_r<=8'hff;
          closing_r<=0;release_allowed_r<=0;release_open_r<=0;
          elapsed_xck_r<=0;close_delay_xck_r<=0;release_window_xck_r<=0;
          noise_f2_gain_r<=0;noise_f5_gain_r<=0;
          ns_x1_r<=0;ns_x2_r<=0;ns_y1_r<=0;ns_y2_r<=0;
          for(i=0;i<6;i=i+1) begin field_r[i]<=0;target_r[i]<=0; end
          for(i=0;i<5;i=i+1) begin
            tract_y1_r[i]<=0;tract_y2_r[i]<=0;
            tract_x1_r[i]<=0;tract_x2_r[i]<=0;
          end
       end else begin
          fc_start_r<=1'b0;
          if(write_i) begin
             case(reg_i)
               3'd0: begin
                  r0<=data_i;
                  if(powered_o) begin
                    remain_xck_r<=duration_ticks(data_i,r2,mode_r);
                    duration_xck_r<=duration_ticks(data_i,r2,mode_r);
                    request_r<=0;
                    elapsed_fc_r<=0;
                    closure_level_r<=8'hff;
                    closing_r<=!die_rom[data_i[5:0]][2];
                    release_allowed_r<=!die_rom[data_i[5:0]][2] && die_rom[data_i[5:0]][1];
                    release_open_r<=0;elapsed_xck_r<=0;
                    close_delay_xck_r<=duration_ticks(data_i,r2,mode_r)>>2;
                    release_window_xck_r<=
                        (duration_ticks(data_i,r2,mode_r)>>2)+
                        (duration_ticks(data_i,r2,mode_r)>>4);
                  end
               end
               3'd1: r1<=data_i;
               3'd2: r2<=data_i;
               3'd3: begin
                  r3<=data_i;
                  if(data_i[7]) begin
                    remain_xck_r<=0;request_r<=0;mode_valid_r<=0;
                  end else if(r3[7]) begin
                    mode_r<=r0[7:6];mode_valid_r<=1;
                    remain_xck_r<=duration_ticks(r0,r2,r0[7:6]);
                    duration_xck_r<=duration_ticks(r0,r2,r0[7:6]);
                    request_r<=0;
                    closing_r<=!die_w[2];
                    release_allowed_r<=!die_w[2] && die_w[1];
                    release_open_r<=0;elapsed_xck_r<=0;
                    close_delay_xck_r<=duration_ticks(r0,r2,r0[7:6])>>2;
                    release_window_xck_r<=
                       (duration_ticks(r0,r2,r0[7:6])>>2)+
                       (duration_ticks(r0,r2,r0[7:6])>>4);
                  end
               end
               default: r4<=data_i;
             endcase
          end
          if(xck_tick_i) begin
             if(powered_o && !write_i) begin
                if(remain_xck_r>1) begin
                   remain_xck_r<=remain_xck_r-1'b1;
                   elapsed_xck_r<=elapsed_xck_r+1'b1;
                   if(release_allowed_r && remain_xck_r<=release_window_xck_r)
                       release_open_r<=1;
                end
                else if(remain_xck_r==1) begin
                   remain_xck_r<=0;request_r<=mode_r!=0;
                end
                if(pitch_div_r<=1) begin
                   pitch_div_r<=desired_pitch_w;
                   pulse_pending_r<=1;
                end else pitch_div_r<=pitch_div_r-1'b1;
                if(fc_div_r+1>=filter_period_w) begin
                   fc_div_r<=0;
                   fc_start_r<=1'b1;
                end else fc_div_r<=fc_div_r+1'b1;
             end
          end
          if(fc_start_r && powered_o && stage_r==0) begin
             // Transition targets are read from the real decoded die ROM.
             target_r[0]<=f1_target_w;target_r[1]<=f2_target_w;
             target_r[2]<=f3_target_w;target_r[3]<=nas_target_w;
             target_r[4]<=va_target_w;target_r[5]<=fa_target_w;
             for(i=0;i<6;i=i+1) begin
                 field_r[i]<=approach16(field_r[i],
                   {target_r[i],12'd0},
                   (i==0)?f1_step_w:((i>=4)?fast_step_w:slow_step_w));
             end
             pitch_target_r<={desired_pitch_target_w,12'd0};
             // Modes 1 and 2 bypass pitch glide in the reference chip;
             // only mode 3 transitions the R1 upper-pitch field.
             pitch_glide_r<= (mode_r==2'd3) ?
                approach24(pitch_glide_r,
                   {desired_pitch_target_w,12'd0},glide_step_w) :
                {desired_pitch_target_w,12'd0};
             amp_r<=approach16(amp_r,{r3[3:0],12'd0},amp_step_w);
             lfsr_r<={lfsr_r[14:0],
                       lfsr_r[15]^lfsr_r[13]^lfsr_r[12]^lfsr_r[10]};
             noise_prev_r<=noise_now_w;
             ns_x2_r<=ns_x1_r;ns_x1_r<=noise_bit_w;
             ns_y2_r<=ns_y1_r;ns_y1_r<=ns_next_w;
             noise_f2_gain_r<=approach16(noise_f2_gain_r,
                  noise_f2_target_w,fast_step_w);
             noise_f5_gain_r<=approach16(noise_f5_gain_r,
                  noise_f5_target_w,fast_step_w);
             if(pulse_pending_r) begin
                 glottal_age_r<=0;
                 pulse_pending_r<=0;
             end else if(glottal_age_r<6'd63)
                glottal_age_r<=glottal_age_r+1'b1;
             // Close after one frame scaled to phoneme length, release
             // approximately 1.25 frames before its original end.
             if(closing_r && elapsed_xck_r>=close_delay_xck_r &&
                !release_open_r) begin
                if(closure_level_r>8'd8) closure_level_r<=closure_level_r-8'd8;
                else closure_level_r<=0;
             end else if(closure_level_r<8'd247)
                closure_level_r<=closure_level_r+8'd8;
             else closure_level_r<=8'hff;
             // start the filter-clock sample's five stage microsequence.
             tract_r<=start_drive_w;
             stage_r<=1;
             elapsed_fc_r<=elapsed_fc_r+1'b1;
          end else if(stage_r!=0) begin
             // Stage index 1..5, matching F1->F2->F3->F4->F5.
             // Synthesis will reuse the arithmetic across five logic cycles.
             tract_r<=next_filter_w;
             tract_x2_r[stage_r-1]<=tract_x1_r[stage_r-1];
             tract_x1_r[stage_r-1]<=drive_w;
             tract_y2_r[stage_r-1]<=tract_y1_r[stage_r-1];
             tract_y1_r[stage_r-1]<=next_filter_w;
             if(stage_r==5) begin
                 stage_r<=0;
                 // high-pass output. The output divider provides the
                 // host PCM clock; this held signal can be resampled.
                 hp_x_r<=next_filter_w;
                 // Explicit 64-bit signed feedback and saturating 32-bit
                 // state. Never let the high-pass pole wrap modulo 2^32.
                 hp_y_r<=hp_next_w;
                 // Scale to PCM at the chip output, never boost an
                 // already contaminated shared HDMI music bus.
                 held_pcm_r<=clip16((($signed(hp_next_w) *
                      OUTPUT_GAIN_NUM) * $signed({1'b0,closure_level_r})) >>> 8);
             end else stage_r<=stage_r+1'b1;
          end
          if(out_count_r == OUTPUT_DIV-1) begin
             out_count_r<=0;
             // Four retained samples plus current sample, 5-tap FIR.
             // Round towards zero via fixed signed arithmetic shift.
             fir3_r<=fir2_r;
             fir2_r<=fir1_r;
             fir1_r<=fir0_r;
             fir0_r<=held_pcm_r;
             pcm_o<=powered_o ? clip16(fir_sum_w >>> 4) : 16'sd0;
          end else out_count_r<=out_count_r+1'b1;
          if(!powered_o) begin
             pcm_o<=0;held_pcm_r<=0;
             fir0_r<=0;fir1_r<=0;fir2_r<=0;fir3_r<=0;
             hp_x_r<=0;hp_y_r<=0;
             stage_r<=0;pitch_div_r<=0;glottal_age_r<=6'd63;
          end
       end
    end
endmodule
