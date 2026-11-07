// Standalone simulation for the MB-DOC bridge.
// No Gowin primitives required. This checks control command order,
// SDRAM waveform initialization, stereo oscillator controls, divider
// frequency results and six independent voices, not actual DOC audio.
`timescale 1ns/1ps
module tb_mb_doc_bridge;
    parameter integer TEST_RES = 1; // compile-time: 0=+2 oct, 1=+1 oct, 2=old pitch
    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic reset_n = 1'b0;
    logic sdram_ready = 1'b0;

    logic l_wr = 0, r_wr = 0;
    logic [3:0] l_reg = 0, r_reg = 0;
    logic [7:0] l_data = 0, r_data = 0;
    // The native YM cores provide real-time envelope levels, while
    // the VIA PB2 outputs deliver each chip's independent reset.
    logic [4:0] l_env_level = 0, r_env_level = 0;
    logic l_reset_n = 1'b1, r_reset_n = 1'b1;

    wire fx_l, fx_r;
    wire doc_wr;
    wire [7:0] doc_addr, doc_data;
    wire ram_wr;
    wire [20:0] ram_addr;
    wire [31:0] ram_data;
    wire [3:0] ram_byte_en;
    logic ram_ready = 0;
    wire active,unused;
    wire [2:0] active_voice;

    mb_doc_bridge #(
        .HOST_SPACING_CYCLES(80),
        .SCAN_PAUSE_CYCLES(128),
        .SUSTAIN_RES(3'(TEST_RES))
    ) dut (
        .clk_i(clk), .reset_n_i(reset_n),
        .sdram_ready_i(sdram_ready),
        .ay_l_wr_i(l_wr), .ay_l_reg_i(l_reg),
        .ay_l_data_i(l_data),
        .ay_r_wr_i(r_wr), .ay_r_reg_i(r_reg),
        .ay_r_data_i(r_data),
        .ay_l_env_level_i(l_env_level),
        .ay_r_env_level_i(r_env_level),
        .ay_l_reset_n_i(l_reset_n),
        .ay_r_reset_n_i(r_reset_n),
        .doc_wr_o(doc_wr), .doc_addr_o(doc_addr),
        .doc_data_o(doc_data),
        .ram_wr_o(ram_wr), .ram_addr_o(ram_addr),
        .ram_data_o(ram_data), .ram_byte_en_o(ram_byte_en),
        .ram_ready_i(ram_ready), .ready_o(active),
        .active_voice_o(active_voice),
        .fx_ay_l_o(fx_l), .fx_ay_r_o(fx_r)
    );

    integer write_count = 0, doc_count = 0;
    integer ram_busy = 0, ram_delay = 0;
    logic prev_ram_wr = 0;
    logic [7:0] doc_addresses [0:255];
    logic [7:0] doc_values [0:255];

    // Independent 5632-byte seven-zone SynthLAB piano sustain fingerprint. This detects a missing,
    // truncated, lane-swapped or stale piano sample during SDRAM preload.
    logic [31:0] sample_fnv = 32'h811C9DC5;

    // Pretend the SDRAM controller acknowledges exactly once.
    always @(posedge clk) begin
        ram_ready <= 1'b0;
        if (!reset_n) begin
            ram_busy <= 0;
            ram_delay <= 0;
            prev_ram_wr <= 0;
            sample_fnv = 32'h811C9DC5;
        end else begin
            prev_ram_wr <= ram_wr;
            if (ram_wr && !prev_ram_wr) begin
                if (ram_busy || write_count >= 1408)
                    $fatal(1, "RAM double request");
                if (ram_addr !== write_count || ram_byte_en !== 4'hF)
                    $fatal(1, "Bad RAM addr/lane %d %h", write_count, ram_addr);
                for (integer lane=0; lane<4; lane=lane+1) begin
                    if (ram_data[lane*8 +:8] == 8'h00)
                        $fatal(1, "Piano PCM contains DOC stop marker word=%0d lane=%0d",
                               write_count, lane);
                    sample_fnv =
                        (sample_fnv ^ {24'h0,ram_data[lane*8 +:8]}) *
                        32'h01000193;
                end
                write_count <= write_count + 1;
                ram_busy <= 1;
                ram_delay <= 4;
            end
            if (ram_busy) begin
                if (ram_delay == 0) begin
                    ram_ready <= 1'b1;
                    ram_busy <= 0;
                end else ram_delay <= ram_delay - 1;
            end
            if (doc_wr) begin
                if (write_count != 1408)
                    $fatal(1, "DOC command before preload complete");
                if (sample_fnv !== 32'h170BB8B3)
                    $fatal(1, "Piano PCM FNV32 mismatch: %h", sample_fnv);
                if (doc_count < 256) begin
                    doc_addresses[doc_count] <= doc_addr;
                    doc_values[doc_count] <= doc_data;
                end
                doc_count <= doc_count + 1;
            end
        end
    end

    task automatic ay_write(
        input logic chip,
        input logic [3:0] reg_id,
        input logic [7:0] data_byte
    );
        @(negedge clk);
        if (chip) begin
            r_reg = reg_id; r_data = data_byte; r_wr = 1;
        end else begin
            l_reg = reg_id; l_data = data_byte; l_wr = 1;
        end
        @(negedge clk);
        l_wr = 0; r_wr = 0;
    endtask

    task automatic voice_setup(
        input integer voice,
        input integer period
    );
        reg chip;
        reg [3:0] base;
        begin
            chip = voice >= 3;
            base = 4'((voice % 3)*2);
            ay_write(chip, base, 8'(period));
            ay_write(chip, base+1, 8'(period>>8));
            ay_write(chip, 4'(8+voice%3), 8'h0F);
        end
    endtask

    function automatic integer period_for(input integer i);
        case(i)
            0:period_for=60;    // D5 zone
            1:period_for=100;   // B3 zone
            2:period_for=150;   // calibrated C3 zone
            3:period_for=250;   // calibrated C3 zone
            4:period_for=800;   // E2 zone
            default:period_for=1800; // C1 zone
        endcase
    endfunction
    function automatic integer zone_wtp_for(input integer period);
        if (period <= 70) zone_wtp_for = 'h14;
        else if (period <= 90) zone_wtp_for = 'h12;
        else if (period <= 112) zone_wtp_for = 'h10;
        else if (period <= 600) zone_wtp_for = 'h0C;
        else if (period <= 1000) zone_wtp_for = 'h08;
        else if (period <= 1600) zone_wtp_for = 'h04;
        else zone_wtp_for = 'h00;
    endfunction

    initial begin
        repeat(4) @(negedge clk);
        reset_n = 1'b1;
        for (integer i=0; i<6; i=i+1)
            voice_setup(i, period_for(i));

        sdram_ready = 1;
        wait (active && doc_count >= 43);
        @(negedge clk);

        if (write_count != 1408 || doc_count < 43)
            $fatal(1, "Startup incomplete %d / %d",write_count,doc_count);
        if (doc_addresses[0] !== 8'hE1 || doc_values[0] !== 8'h0E)
            $fatal(1, "Osc enable incorrect");
        for (integer v=0;v<6;v=v+1) begin
            integer off, expect_fc;
            off = 1 + v*7;
            expect_fc = 93623 / period_for(v);
            if (doc_addresses[off] !== 8'(8'hA0+v) ||
                doc_values[off] !== (v < 3 ? 8'h11 : 8'h01))
                $fatal(1, "Voice %0d initial HALT bad",v);
            if (doc_addresses[off+1] !== 8'(8'h80+v) ||
                doc_values[off+1] !== 8'(zone_wtp_for(period_for(v))))
                $fatal(1, "Voice %0d WTP bad",v);
            if (doc_addresses[off+2] !== 8'(8'hC0+v) ||
                doc_values[off+2] !== 8'((period_for(v) <= 112 ? 8'h08 : 8'h10) | TEST_RES))
                $fatal(1, "Voice %0d RTS bad",v);
            if (doc_addresses[off+3] !== 8'(v) ||
                doc_values[off+3] !== 8'(expect_fc))
                $fatal(1,"Voice %0d freq low got %h expected %h",
                       v,doc_values[off+3],8'(expect_fc));
            if (doc_addresses[off+4] !== 8'(8'h20+v) ||
                doc_values[off+4] !== 8'(expect_fc>>8))
                $fatal(1,"Voice %0d freq high bad",v);
            if (doc_addresses[off+5] !== 8'(8'h40+v) ||
                doc_values[off+5] !== 8'd208)
                $fatal(1,"Voice %0d volume bad",v);
            if (doc_addresses[off+6] !== 8'(8'hA0+v) ||
                doc_values[off+6] !== (v < 3 ? 8'h10 : 8'h00))
                $fatal(1,"Voice %0d RUN/stereo bad",v);
        end
        // Update the leftmost channel while its oscillator is
        // running. The second scan MUST NOT HALT and retrigger
        // its phase; it only changes FC/volume/control.
        ay_write(1'b0, 4'h8, 8'h00);
        wait (doc_count >= 47);
        @(negedge clk);
        if (doc_addresses[43] !== 8'h00 ||
            doc_addresses[44] !== 8'h20 ||
            doc_addresses[45] !== 8'h40 ||
            doc_addresses[46] !== 8'hA0 ||
            doc_values[45] !== 8'h00 ||
            doc_values[46] !== 8'h11)
            $fatal(1, "Retrigger or volume-mute regression");

        // MCS uses period $0001 as a rest: the DOC must not play
        // aliased ultrasonic garbage even if AY fixed volume is nonzero.
        ay_write(1'b0, 4'h0, 8'h01);
        ay_write(1'b0, 4'h1, 8'h00);
        ay_write(1'b0, 4'h8, 8'h0F);
        // The new value is visible on the next round of voice0.
        wait (doc_count >= 71);
        @(negedge clk);
        if (doc_addresses[67] !== 8'h00 ||
            doc_addresses[68] !== 8'h20 ||
            doc_values[67] !== 8'hFF ||
            doc_values[68] !== 8'hFF)
            $fatal(1, "Period-one frequency clamp incorrect");

        // Rest with nonzero AY volume must actually mute DOC, including CTRL.
        if (doc_values[69] !== 8'h00 || doc_values[70] !== 8'h11)
            $fatal(1, "MCS period-one rest leaked DOC sound");

        // A valid new note following that rest must restart the oscillator
        // and select the calibrated C3 sustain at WTP $0C.
        l_env_level = 5'd31;
        ay_write(1'b0, 4'h0, 8'd145); // A4 keyboard test
        ay_write(1'b0, 4'h8, 8'h10);
        wait (doc_count >= 98);
        @(negedge clk);
        if (doc_addresses[91] !== 8'hA0 || doc_values[91] !== 8'h11 ||
            doc_addresses[92] !== 8'h80 || doc_values[92] !== 8'h0C ||
            doc_addresses[93] !== 8'hC0 || doc_values[93] !== (8'h10|TEST_RES) ||
            doc_addresses[96] !== 8'h40 || doc_values[96] !== 8'd208 ||
            doc_addresses[97] !== 8'hA0 || doc_values[97] !== 8'h10)
            $fatal(1, "P4 note retrigger or preserved keyboard envelope failed");

        // The native YM envelope must still control keyboard decay.
        l_env_level = 5'd0;
        wait (doc_count >= 122);
        @(negedge clk);
        if (doc_addresses[120] !== 8'h40 ||
            doc_values[120] !== 8'h00 ||
            doc_values[121] !== 8'h11)
            $fatal(1, "Native R13 envelope mute failed");

        // Upward software volume change, even on an identical pitch, is an
        // MCS note re-strike. A new one-shot piano envelope must start.
        ay_write(1'b0, 4'h8, 8'h0F);
        wait (doc_count >= 149);
        @(negedge clk);
        if (doc_addresses[142] !== 8'hA0 || doc_values[142] !== 8'h11 ||
            doc_addresses[143] !== 8'h80 || doc_values[143] !== 8'h0C ||
            doc_addresses[147] !== 8'h40 || doc_values[147] !== 8'd208 ||
            doc_addresses[148] !== 8'hA0 || doc_values[148] !== 8'h10)
            $fatal(1, "MCS same-pitch amplitude re-strike failed");

        // PB2 reset must clear shadows and silence a running DOC voice.
        l_reset_n = 1'b0;
        repeat (3) @(negedge clk);
        l_reset_n = 1'b1;
        wait (doc_count >= 173);
        @(negedge clk);
        if (doc_addresses[171] !== 8'h40 ||
            doc_values[171] !== 8'h00 ||
            doc_values[172] !== 8'h11)
            $fatal(1, "P4 PSG reset failed");

        $display("PASS: native AY envelope level, zero-vol note-off, PB2 reset");
        // Title animation FX signature ($1C, 15/15) and native AY noise.
        ay_write(1'b0, 4'h7, 8'h1C);
        ay_write(1'b0, 4'h8, 8'h0F);
        ay_write(1'b0, 4'h9, 8'h0F);
        if (fx_l !== 1'b1) $fatal(1, "Startup 2-tone glide AY bypass missing");
        ay_write(1'b0, 4'h7, 8'h3E);
        if (fx_l !== 1'b0) $fatal(1, "Keyboard wrongly bypasses sampled piano");
        ay_write(1'b1, 4'h7, 8'h07);
        ay_write(1'b1, 4'h8, 8'h10);
        if (fx_r !== 1'b1) $fatal(1, "AY noise bypass missing");

        $display("PASS: seven authentic PCM zones 5632B; RES=%0d, period-one rest, note restart, FX bypass", TEST_RES);
        $display("      continued phase, mute, and period-zero pitch clamp");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1,"Timeout boot/first six voices: RAM=%0d DOC=%0d",
               write_count,doc_count);
    end
endmodule
