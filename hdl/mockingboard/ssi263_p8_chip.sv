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
    parameter integer OUTPUT_HZ = 16_000,
    parameter integer FRAME_XCK = 4096
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
    logic [3:0] glottal_age_r;
    logic [15:0] lfsr_r;
    logic signed [15:0] noise_prev_r;
    logic [7:0] output_div_r;
    localparam integer OUTPUT_DIV=LOGIC_HZ/OUTPUT_HZ;
    localparam integer OUTCW=$clog2(OUTPUT_DIV);
    logic [OUTCW-1:0] out_count_r;
    logic signed [15:0] held_pcm_r;
    logic signed [31:0] hp_x_r,hp_y_r;
    logic [2:0] stage_r;
    logic signed [31:0] tract_r;
    logic signed [31:0] tract_y1_r[0:4],tract_y2_r[0:4];
    logic signed [31:0] tract_x1_r[0:4],tract_x2_r[0:4];
    logic [11:0] field_r[0:5];  // 4-bit code plus 8-bit sub-code
    logic [3:0] target_r[0:5];
    logic [7:0] amp_r;
    logic [11:0] pitch_glide_r;
    logic [11:0] pitch_target_r;
    logic [15:0] elapsed_fc_r;
    logic [15:0] frame_fc_r;
    logic [7:0] closure_level_r;

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
    wire [11:0] combined_pitch_w=pitch_glide_r+imm_pitch_w;
    wire [15:0] desired_pitch_w=(16'd4096-combined_pitch_w)<<3;
    wire [11:0] desired_pitch_target_w=
        (mode_r==2'd3) ? {r1[7:3],6'b0} : {r1,3'b0};
    wire [11:0] current_advance_w =
        // Q8 sub-code per filter tick, adjusted for frame length.
        (({8'd0,r3[6:4]}+12'd5) << 5) /
        (12'd1+{8'd0,r2[7:4]}); // preliminary transition scaling
    wire [11:0] slow_step_w =
        (current_advance_w==0) ? 12'd1 : current_advance_w;
    wire [11:0] fast_step_w=slow_step_w*6;

    // One shared section-processing slot, five passes per filter sample.
    // Avoid a five-biquad combinational DSP cascade on the 54 MHz path.
    wire [5:0] coeff_index_w =
        (stage_r==3'd0) ? {2'b00,field_r[0][11:8]} :
        (stage_r==3'd1) ? {2'b01,field_r[1][11:8]} :
        (stage_r==3'd2) ? {2'b10,field_r[2][11:8]} :
        (stage_r==3'd3) ? 6'd48 : 6'd49;
    wire [55:0] coeff_w=coefficient_rom[coeff_index_w];
    wire signed [15:0] a1_w=coeff_w[55:40];
    wire signed [15:0] a2_w=coeff_w[39:24];
    wire signed [23:0] gain_w={1'b0,coeff_w[22:0]};
    wire signed [63:0] bilinear_input_w=
        $signed(tract_r)+($signed(tract_x1_r[stage_r])<<<1)+
        $signed(tract_x2_r[stage_r]);
    wire signed [63:0] filter_sum_w=
        (($signed(gain_w)*bilinear_input_w) >>> 24)+
        (($signed(a1_w)*$signed(tract_y1_r[stage_r]))>>>14)-
        (($signed(a2_w)*$signed(tract_y2_r[stage_r]))>>>14);
    wire signed [31:0] next_filter_w=clip32(filter_sum_w);
    wire signed [15:0] noise_now_w=
        $signed({8'b0,lfsr_r[7:0]})-16'sd128;
    wire signed [15:0] shaped_noise_w=noise_now_w-noise_prev_r;
    wire signed [15:0] glottal_w=
        (glottal_age_r==4'd0) ? 16'sd24576 :
        (glottal_age_r==4'd1) ? 16'sd21 :
        (glottal_age_r==4'd2) ? 16'sd80 :
        (glottal_age_r==4'd3) ? 16'sd176 :
        (glottal_age_r==4'd4) ? 16'sd300 :
        (glottal_age_r==4'd5) ? 16'sd438 :
        (glottal_age_r==4'd6) ? 16'sd584 :
        (glottal_age_r==4'd7) ? 16'sd730 :
        (glottal_age_r==4'd8) ? 16'sd844 :
        (glottal_age_r==4'd9) ? 16'sd941 :
        (glottal_age_r==4'd10) ? 16'sd1017 :
        (glottal_age_r==4'd11) ? 16'sd1022 :
        (glottal_age_r==4'd12) ? 16'sd943 :
        (glottal_age_r==4'd13) ? 16'sd745 :
        (glottal_age_r==4'd14) ? 16'sd391 : 16'sd0;
    wire [15:0] amplitude_w={8'd0,amp_r};
    wire signed [31:0] voice_source_w=
        ($signed(glottal_w)*$signed({1'b0,field_r[4][11:8]})*
        $signed({1'b0,amplitude_w}))>>>12;
    wire signed [31:0] noise_source_w=
        ($signed(shaped_noise_w)*$signed({1'b0,field_r[5][11:8]})*
         $signed({1'b0,amplitude_w}))>>>8;
    wire signed [31:0] start_drive_w=
        (!powered_o || r0[5:0]==6'd0 || r0[5:0]==6'd63 ||
         (!closure_clear_w && closure_level_r==0)) ? 32'sd0 :
        voice_source_w;
    wire signed [31:0] filter_drive_w =
        (stage_r==3'd1 && route_f2_w) ? tract_r+noise_source_w :
        (stage_r==3'd4 && !route_f2_w) ? tract_r+noise_source_w :
        tract_r;

    integer i;
    always_ff @(posedge clk_i) begin
       if (!reset_n_i) begin
          r0<=0; r1<=0; r2<=0; r3<=8'h80; r4<=0;
          mode_r<=0; mode_valid_r<=0; request_r<=0;
          duration_xck_r<=0; remain_xck_r<=0;
          frame_xck_r<=0; filter_xck_r<=0;
          fc_div_r<=0; fc_start_r<=0;
          pitch_xck_r<=0; pitch_div_r<=0; pulse_pending_r<=0;
          glottal_age_r<=4'hf; lfsr_r<=16'hace1;
          noise_prev_r<=0;
          out_count_r<=0; held_pcm_r<=0; pcm_o<=0;
          hp_x_r<=0; hp_y_r<=0;
          stage_r<=0; tract_r<=0;
          amp_r<=0; pitch_glide_r<=0; pitch_target_r<=0;
          elapsed_fc_r<=0; frame_fc_r<=0; closure_level_r<=8'hff;
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
                  end
               end
               default: r4<=data_i;
             endcase
          end
          if(xck_tick_i) begin
             if(powered_o && !write_i) begin
                if(remain_xck_r>1) remain_xck_r<=remain_xck_r-1'b1;
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
                 field_r[i]<=approach(field_r[i],
                   {target_r[i],8'd0}, (i>=4)?fast_step_w:slow_step_w);
             end
             pitch_target_r<=desired_pitch_target_w;
             pitch_glide_r<=approach(pitch_glide_r,pitch_target_r,12'd4);
             if(amp_r<{4'd0,r3[3:0]}) amp_r<=amp_r+1'b1;
             else if(amp_r>{4'd0,r3[3:0]}) amp_r<=amp_r-1'b1;
             lfsr_r<={lfsr_r[14:0],
                       lfsr_r[15]^lfsr_r[13]^lfsr_r[12]^lfsr_r[10]};
             noise_prev_r<=noise_now_w;
             if(pulse_pending_r) begin
                 glottal_age_r<=0;
                 pulse_pending_r<=0;
             end else if(glottal_age_r<15) glottal_age_r<=glottal_age_r+1'b1;
             if(!closure_clear_w) begin
                if(closure_level_r>4) closure_level_r<=closure_level_r-4;
                else closure_level_r<=0;
             end else if(closure_level_r<8'hfb)
                closure_level_r<=closure_level_r+4;
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
             tract_x1_r[stage_r-1]<=tract_r;
             tract_y2_r[stage_r-1]<=tract_y1_r[stage_r-1];
             tract_y1_r[stage_r-1]<=next_filter_w;
             if(stage_r==5) begin
                 stage_r<=0;
                 // high-pass output. The output divider provides the
                 // host PCM clock; this held signal can be resampled.
                 hp_x_r<=next_filter_w;
                 hp_y_r<=next_filter_w-hp_x_r+
                         ((hp_y_r*32'sd32100)>>>15);
                 held_pcm_r<=clip16((next_filter_w-hp_x_r+
                          ((hp_y_r*32'sd32100)>>>15))>>>2);
             end else stage_r<=stage_r+1'b1;
          end
          if(out_count_r == OUTPUT_DIV-1) begin
             out_count_r<=0;
             pcm_o<=powered_o ? held_pcm_r : 16'sd0;
          end else out_count_r<=out_count_r+1'b1;
          if(!powered_o) begin
             pcm_o<=0;held_pcm_r<=0;
             stage_r<=0;pitch_div_r<=0;glottal_age_r<=4'hf;
          end
       end
    end
endmodule
