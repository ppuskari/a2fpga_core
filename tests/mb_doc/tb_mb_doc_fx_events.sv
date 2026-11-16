`timescale 1ns/1ps
// Self-contained AY sound-effects event decoder regression (no commercial
// song data, no FPGA IP, no changes to the golden DOC piano renderer).
module tb_mb_doc_fx_events;
    logic clk=0,reset_n=0;
    always #5 clk=~clk;
    logic [1:0] chip_reset_n=2'b11, publish=0,r13_write=0;
    logic [1:0][7:0] mixer;
    logic [1:0][4:0] noise_period,env_level;
    logic [1:0][2:0][4:0] amp;
    logic [1:0][3:0] env_shape;
    wire [1:0] valid;
    wire [1:0][2:0] patch,noise_mask,tone_mask,env_mask;
    wire [1:0][7:0] velocity;
    wire [1:0][4:0] event_noise;
    wire [1:0][3:0] event_shape;
    mb_doc_fx_events #(
        .ENABLE(1'b1),
        .NOISE_MOD_COOLDOWN_CYCLES(10)
    ) dut (
        .clk_i(clk),.reset_n_i(reset_n),.chip_reset_n_i(chip_reset_n),
        .publish_i(publish),.r13_write_i(r13_write),
        .mixer_i(mixer),.noise_period_i(noise_period),.amp_i(amp),
        .env_level_i(env_level),.env_shape_i(env_shape),
        .event_valid_o(valid),.event_patch_o(patch),
        .event_velocity_o(velocity),.event_noise_mask_o(noise_mask),
        .event_tone_mask_o(tone_mask),.event_envelope_mask_o(env_mask),
        .event_noise_period_o(event_noise),
        .event_envelope_shape_o(event_shape)
    );

    task automatic commit(input [1:0] mask);
        @(negedge clk);
        publish=mask;
        @(negedge clk);
        publish=0;
        #1;
    endtask
    initial begin
        mixer='1; noise_period='0;env_level='0;env_shape='0; amp='0;
        repeat(3) @(negedge clk);
        reset_n=1;
        // Normal fixed-volume piano A. Tone A on; noise all disabled.
        mixer[0]=8'h3E; amp[0][0]=5'h0F;
        noise_period[0]=5'd20;
        commit(2'b01);
        if(valid!==2'b00) $fatal(1,"Piano-only frame incorrectly emitted FX");

        // Same channel now has tone + noise. This is not a new piano:
        // the future player must launch an FX layer on OSC6/7.
        mixer[0]=8'h36;
        commit(2'b01);
        if(valid!==2'b01 || patch[0]!==3'd5 ||
           noise_mask[0]!==3'b001 || tone_mask[0]!==3'b001 ||
           velocity[0]!==8'd240 || event_noise[0]!==5'd20)
            $fatal(1,"AY mixed tone/noise FX decode incorrect");
        commit(2'b00);
        if(valid!==2'b00) $fatal(1,"Event pulse stuck high");

        // R6 changes can sweep rapidly during title software effects.
        // The cooldown prevents triggering a new one-shot on every
        // intermediate noise period variation.
        noise_period[0]=5'd21;
        commit(2'b01);
        if(valid[0]) $fatal(1,"Noise sweep retriggered inside cooldown");
        repeat(15) @(negedge clk);
        noise_period[0]=5'd22;
        commit(2'b01);
        if(!valid[0]) $fatal(1,"Noise period change did not retrigger after guard");

        // AY R13 rewrites repeat the same envelope shape and still
        // restart its phase. The raw write must survive until publication.
        mixer[0]=8'h37; // tone A off, noise A on
        amp[0][0]=5'h10; // envelope mode, independent of fixed vol
        env_level[0]=5'd12;
        env_shape[0]=4'hA;
        repeat(15) @(negedge clk);
        commit(2'b01);
        @(negedge clk);
        r13_write[0]=1'b1;
        @(negedge clk);
        r13_write[0]=1'b0;
        commit(2'b01);
        if(valid[0]!==1'b1 || env_mask[0]!==3'b001 ||
           event_shape[0]!==4'hA || velocity[0]!==8'd96)
            $fatal(1,"Same-value R13 envelope restart lost");

        // Right PSG has a separate noise source and event.
        mixer[1]=8'h3D; // tone B on, noise A? remains disabled
        amp[1][1]=5'h0F;
        commit(2'b10);
        if(valid[1]) $fatal(1,"Right tone-only music produced FX");
        mixer[1]=8'h2D; // noise B on (bit4 clear)
        noise_period[1]=5'd3;
        commit(2'b10);
        if(valid!==2'b10 || patch[1]!==3'd1 ||
           noise_mask[1]!==3'b010)
            $fatal(1,"Independent right PSG noise/mixed event failed");
        // Chip reset independently cancels history; reactivation starts anew.
        @(negedge clk);
        chip_reset_n[0]=0;
        @(negedge clk);
        chip_reset_n[0]=1;
        amp[0][0]=0;
        commit(2'b01);
        if(valid[0]) $fatal(1,"Reset left FX should not retrigger");
        amp[0][0]=5'h0F;
        commit(2'b01);
        if(!valid[0] || valid[1])
            $fatal(1,"Independent left reactivation after PSG reset failed");
        $display("PASS: AY tone/noise masks, fixed/envelope volumes, R13 restart");
        $display("PASS: independent stereo PSG, R6 retrigger guard, no piano hijack");
        $finish;
    end
    initial begin
        #200000;
        $fatal(1,"FX event regression timeout");
    end
endmodule
