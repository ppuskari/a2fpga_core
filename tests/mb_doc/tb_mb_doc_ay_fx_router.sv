`timescale 1ns/1ps
module tb_mb_doc_ay_fx_router;
    reg [1:0] reset_n=2'b11;
    reg [1:0][7:0] mixer='1;
    reg [1:0][2:0][4:0] amp='0;
    reg [1:0] glide=0;
    wire [1:0][2:0] selected,all_native,disabled;
    mb_doc_ay_fx_router #(.ENABLE(1'b1),.FORCE_NATIVE_ALL(1'b0))
    normal (.chip_reset_n_i(reset_n),.mixer_i(mixer),
        .amplitude_i(amp),.title_glide_confirmed_i(glide),
        .native_mask_o(selected));
    mb_doc_ay_fx_router #(.ENABLE(1'b1),.FORCE_NATIVE_ALL(1'b1))
    force_all (.chip_reset_n_i(reset_n),.mixer_i(mixer),
        .amplitude_i(amp),.title_glide_confirmed_i(glide),
        .native_mask_o(all_native));
    mb_doc_ay_fx_router #(.ENABLE(1'b0),.FORCE_NATIVE_ALL(1'b1))
    off (.chip_reset_n_i(reset_n),.mixer_i(mixer),
        .amplitude_i(amp),.title_glide_confirmed_i(glide),
        .native_mask_o(disabled));

    task automatic assert_masks(input [5:0] want, input [255:0] why);
        begin
            #1;
            if (selected !== want)
                $fatal(1,"%0s got native mask %06b expected %06b",why,selected,want);
            if (disabled !== 6'b000000)
                $fatal(1,"Disabled mode must preserve golden DOC piano exclusively");
        end
    endtask
    initial begin
        // Two simultaneous melodic chords: both chips remain six DOC piano.
        mixer[0]=8'h3E; amp[0][0]=5'h0F;
        mixer[1]=8'h3D; amp[1][1]=5'h0F;
        assert_masks(6'b000000,"Two-chip piano with no noise");
        if (all_native!==6'b111111)
            $fatal(1,"Diagnostic force-all must bypass all six DOC voices");

        // Enable shared noise on AY left A. Tone+noise *belongs together*
        // on native YM channel A, not a classified snare sample.
        mixer[0]=8'h36;
        assert_masks(6'b000001,"Noise A plus tone A");

        // Right B independent: left piano B/C and right A/C not stolen.
        mixer[1]=8'h2D;
        assert_masks(6'b010001,"Left A noise and right B noise");
        mixer[0]=8'h3E;
        assert_masks(6'b010000,"Left A returned to piano");

        // Envelope-controlled noise remains selected even at instantaneous
        // zero envelope; otherwise drum attacks get truncated at R13.
        mixer[0]=8'h37;
        amp[0][0]=5'h10;
        assert_masks(6'b010001,"Envelope noise at zero output level");

        // Triple-envelope tone effects are programmable AY even if no
        // noise generator is enabled.
        mixer[0]=8'h38;
        amp[0][0]=5'h10; amp[0][1]=5'h10; amp[0][2]=5'h10;
        assert_masks(6'b010111,"Triple-envelope tone FX on left");

        // M6 confirmed title sweep: two YM tones transition together
        // without a series of piano reattacks, while unrelated right
        // piano/noise channels are unaffected.
        mixer[0]=8'h1C; amp[0][0]=5'h0F; amp[0][1]=5'h0F;
        amp[0][2]=0; glide[0]=1;
        assert_masks(6'b010011,"Confirmed title tone sweep A/B");
        glide[0]=0;
        assert_masks(6'b010000,"Expired title sweep restores piano");

        // Left PSG reset removes only left FX routes, right unaffected.
        reset_n[0]=0;
        mixer[0]=8'h37; amp[0][0]=5'h0F;
        assert_masks(6'b010000,"Left chip reset");
        reset_n[0]=1;
        assert_masks(6'b010001,"Left sound returns after reset");

        // Independent stereo: right-side reset must not mute left.
        reset_n[1]=0;
        assert_masks(6'b000001,"Right chip reset");
        $display("PASS: per-channel YM FX routing of tone/noise/envelope and title glide");
        $display("PASS: no whole-chip piano hijack, stereo independence, fallback disabled");
        $finish;
    end
endmodule
