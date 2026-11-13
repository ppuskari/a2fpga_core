// M6.4 DOC-only de-click regression: no Gowin IP needed.
`timescale 1ns/1ps
module tb_mb_doc_declick;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0, sdram_ready = 0;
    logic l_wr = 0, r_wr = 0;
    logic [3:0] l_reg = 0, r_reg = 0;
    logic [7:0] l_data = 0, r_data = 0;
    logic ram_ready = 0;
    logic [4:0] env_level = 0;
    wire doc_wr, ram_wr, ready, fx_l, fx_r;
    wire [7:0] doc_addr, doc_data;
    wire [20:0] ram_addr;
    wire [31:0] ram_data;
    wire [3:0] ram_byte_en;
    wire [2:0] active_voice;

    mb_doc_bridge #(
        .HOST_SPACING_CYCLES(16),
        .SCAN_PAUSE_CYCLES(64),
        .DECLICK_ENABLE(1'b1),
        .DECLICK_ATTACK_STEP(8'd16),
        .DECLICK_RELEASE_STEP(8'd12),
        .FX_AY_BYPASS_ENABLE(1'b0)
    ) dut (
        .clk_i(clk), .reset_n_i(reset_n),
        .sdram_ready_i(sdram_ready),
        .ay_l_wr_i(l_wr), .ay_l_reg_i(l_reg), .ay_l_data_i(l_data),
        .ay_r_wr_i(r_wr), .ay_r_reg_i(r_reg), .ay_r_data_i(r_data),
        .ay_l_env_level_i(env_level), .ay_r_env_level_i(env_level),
        .ay_l_reset_n_i(1'b1), .ay_r_reset_n_i(1'b1),
        .doc_wr_o(doc_wr), .doc_addr_o(doc_addr), .doc_data_o(doc_data),
        .ram_wr_o(ram_wr), .ram_addr_o(ram_addr), .ram_data_o(ram_data),
        .ram_byte_en_o(ram_byte_en), .ram_ready_i(ram_ready),
        .ready_o(ready), .active_voice_o(active_voice),
        .fx_ay_l_o(fx_l), .fx_ay_r_o(fx_r)
    );

    integer ram_count=0, ram_busy=0, ram_delay=0;
    logic prev_ram_wr=0;
    always @(posedge clk) begin
        ram_ready <= 0;
        if (!reset_n) begin
            prev_ram_wr <= 0;
            ram_busy <= 0;
        end else begin
            prev_ram_wr <= ram_wr;
            if (ram_wr && !prev_ram_wr) begin
                if (ram_busy || ram_count>=1408 ||
                    ram_addr!==ram_count || ram_byte_en!==4'hF)
                    $fatal(1,"Unexpected DOC sample upload at %0d",ram_count);
                ram_count <= ram_count+1;
                ram_busy <= 1;
                ram_delay <= 2;
            end
            if (ram_busy) begin
                if (ram_delay==0) begin
                    ram_ready <= 1;
                    ram_busy <= 0;
                end else ram_delay <= ram_delay-1;
            end
        end
    end

    integer phase=0, count_vol=0, count_halt=0, count_wtp=0;
    integer first_attack=0, attack_steps=0, release_steps=0;
    integer prev_volume=0, last_volume=0;
    integer last_volume_update=0;
    logic had_zero_before_halt=1;
    // Monitor only voice 0; every other melodic oscillator continues
    // through the normal six-voice scanner.
    always @(posedge clk) if (reset_n && doc_wr) begin
        if (doc_addr==8'h80) count_wtp = count_wtp+1;
        if (doc_addr==8'h40) begin
            last_volume = int'(doc_data);
            count_vol = count_vol+1;
            if (phase==1 || phase==3 || phase==5) begin
                if (last_volume > prev_volume+16)
                    $fatal(1,"Attack exceeded 16/scan: %0d -> %0d",
                           prev_volume,last_volume);
                if (phase==1 && first_attack==0) begin
                    if (last_volume != 0)
                        $fatal(1,"First DOC note must start at VOL=0");
                    first_attack=1;
                end
                if (last_volume > prev_volume) attack_steps++;
            end
            if (phase==2 || phase==4) begin
                if (last_volume > prev_volume)
                    $fatal(1,"Release grew instead of faded: %0d -> %0d",
                           prev_volume,last_volume);
                if (prev_volume > last_volume+12)
                    $fatal(1,"Release exceeded 12/scan: %0d -> %0d",
                           prev_volume,last_volume);
                if (last_volume < prev_volume) release_steps++;
            end
            prev_volume=last_volume;
            last_volume_update=count_vol;
        end
        // A physical DOC HALT is legal only if the most recent
        // voice-zero VOL is already zero.
        if (doc_addr==8'hA0 && doc_data[0]) begin
            count_halt=count_halt+1;
            if (phase>=2 && last_volume!=0)
                $fatal(1,"Abrupt HALT with active volume=%0d",last_volume);
        end
        if (fx_l || fx_r)
            $fatal(1,"Native AY FX override active in DOC-only test");
    end

    task automatic ay_write(input logic [3:0] addr,
                            input logic [7:0] value);
        @(negedge clk);
        l_reg=addr; l_data=value; l_wr=1;
        @(negedge clk);
        l_wr=0;
    endtask

    initial begin : exercise
        integer halt_before, wtp_before;
        repeat (4) @(negedge clk);
        reset_n=1;
        // Only chip-left tone A is active; fixed-volume MCS behavior.
        ay_write(4'h7,8'h3E);
        ay_write(4'h0,8'd145);
        ay_write(4'h1,8'd0);
        ay_write(4'h8,8'h0F);
        phase=1; prev_volume=0;
        sdram_ready=1;
        wait (ready && last_volume>=200);
        @(negedge clk);
        if (!first_attack || attack_steps<10)
            $fatal(1,"DOC note-on did not ramp in");

        phase=2;
        prev_volume=last_volume;
        ay_write(4'h8,8'h00);
        wait (last_volume==0 && count_vol>20);
        @(negedge clk);
        if (release_steps<10)
            $fatal(1,"DOC note-off did not fade");
        wait (count_halt>=2); // startup HALT, then release-complete HALT
        @(negedge clk);
        $display("PASS: note-off release ends at VOL=0 before DOC HALT");

        phase=3;
        prev_volume=last_volume;
        ay_write(4'h8,8'h0F);
        wait (last_volume>=190);
        @(negedge clk);
        if (attack_steps<20)
            $fatal(1,"Note reactivation never ramped back in");

        // Reduce MCS software volume without a restart. Then make a
        // same-pitch upward step >=3/15, which must trigger fade/HALT/
        // WTP/RTS/restart and reattack instead of an audible phase cut.
        phase=0;
        ay_write(4'h8,8'h04);
        wait (last_volume<=60);
        @(negedge clk);
        phase=4;
        prev_volume=last_volume;
        halt_before=count_halt;
        wtp_before=count_wtp;
        ay_write(4'h8,8'h0F);
        wait (count_halt>halt_before);
        @(negedge clk);
        if (last_volume!=0)
            $fatal(1,"Retrigger HALT occurred before fade reached zero");
        if (release_steps<12)
            $fatal(1,"Retrigger lacked a downward ramp");
        phase=5;
        prev_volume=last_volume;
        wait (count_wtp>wtp_before && last_volume>=160);
        @(negedge clk);
        if (attack_steps<25)
            $fatal(1,"Retrigger lacked post-HALT attack");
        $display("PASS: MCS same-pitch re-strike fades out/in without abrupt HALT");
        $display("PASS: DOC-only M6.4 six-voice de-click RTL simulation");
        $finish;
    end

    initial begin
        #10000000;
        $fatal(1,"M6.4 timeout: RAM=%0d VOL=%0d phase=%0d",ram_count,last_volume,phase);
    end
endmodule
