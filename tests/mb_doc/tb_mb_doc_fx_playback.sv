`timescale 1ns/1ps
module tb_mb_doc_fx_playback;
    logic clk=0,reset_n=0,sdram_ready=0;
    always #5 clk=~clk;
    logic l_wr=0,r_wr=0,l_reset_n=1,r_reset_n=1;
    logic [3:0] l_reg=0,r_reg=0;
    logic [7:0] l_data=0,r_data=0;
    wire doc_wr,ram_wr,ready,fx_l,fx_r;
    wire [7:0] doc_addr,doc_data;
    wire [20:0] ram_addr;
    wire [31:0] ram_data;
    wire [3:0] ram_be;
    logic ram_ready=0;
    wire [2:0] active_voice;
    mb_doc_bridge #(
        .HOST_SPACING_CYCLES(16),
        .SCAN_PAUSE_CYCLES(64),
        .COHERENT_PUBLISH_ENABLE(1'b0),
        .FX_EVENT_CAPTURE_ENABLE(1'b1),
        .SAMPLED_FX_ENABLE(1'b1),
        .FX_AY_BYPASS_ENABLE(1'b0),
        .DECLICK_ENABLE(1'b1)
    ) dut (
        .clk_i(clk),.reset_n_i(reset_n),.sdram_ready_i(sdram_ready),
        .ay_l_wr_i(l_wr),.ay_l_reg_i(l_reg),.ay_l_data_i(l_data),
        .ay_r_wr_i(r_wr),.ay_r_reg_i(r_reg),.ay_r_data_i(r_data),
        .ay_l_env_level_i(5'd31),.ay_r_env_level_i(5'd31),
        .ay_l_reset_n_i(l_reset_n),.ay_r_reset_n_i(r_reset_n),
        .doc_wr_o(doc_wr),.doc_addr_o(doc_addr),.doc_data_o(doc_data),
        .ram_wr_o(ram_wr),.ram_addr_o(ram_addr),
        .ram_data_o(ram_data),.ram_byte_en_o(ram_be),.ram_ready_i(ram_ready),
        .ready_o(ready),.active_voice_o(active_voice),
        .fx_ay_l_o(fx_l),.fx_ay_r_o(fx_r)
    );
    integer writes=0, wait_cycles=0;
    logic ram_prev_wr=0;
    logic ram_busy=0;
    always @(posedge clk) begin
        ram_ready<=0;
        if (!reset_n) begin
            ram_prev_wr<=0;ram_busy<=0;writes<=0;
        end else begin
            ram_prev_wr<=ram_wr;
            if(ram_wr && !ram_prev_wr) begin
                if(ram_busy || ram_be!==4'hF)
                    $fatal(1,"Bad SDRAM host handshake");
                if (writes<1408) begin
                    if (ram_addr !== writes)
                        $fatal(1,"Golden piano RAM address changed: %0d",writes);
                end else if (ram_addr !== 21'(2048+(writes-1408)))
                    $fatal(1,"FX RAM address not sequential: %0d",writes);
                ram_busy<=1;
                wait_cycles<=2;
                writes<=writes+1;
            end
            if(ram_busy) begin
                if (wait_cycles==0) begin
                    ram_ready<=1;
                    ram_busy<=0;
                end else wait_cycles<=wait_cycles-1;
            end
        end
    end

    integer l_fx_halts=0,l_fx_wtp=0,l_fx_run=0;
    integer r_fx_halts=0,r_fx_wtp=0,r_fx_run=0;
    integer piano_wtp=0;
    integer fx6_count=0,fx7_count=0;
    logic [7:0] fx6_addrs[0:7],fx6_data[0:7];
    logic [7:0] fx7_addrs[0:7],fx7_data[0:7];
    always @(posedge clk) if(reset_n && doc_wr) begin
        if(doc_addr==8'hA6 || doc_addr==8'h86 ||
           doc_addr==8'hC6 || doc_addr==8'h06 ||
           doc_addr==8'h26 || doc_addr==8'h46) begin
            if(fx6_count<8) begin
                fx6_addrs[fx6_count]=doc_addr;
                fx6_data[fx6_count]=doc_data;
            end
            fx6_count++;
        end
        if(doc_addr==8'hA7 || doc_addr==8'h87 ||
           doc_addr==8'hC7 || doc_addr==8'h07 ||
           doc_addr==8'h27 || doc_addr==8'h47) begin
            if(fx7_count<8) begin
                fx7_addrs[fx7_count]=doc_addr;
                fx7_data[fx7_count]=doc_data;
            end
            fx7_count++;
        end
        if(doc_addr==8'h86 && doc_data==8'h50) l_fx_wtp++;
        if(doc_addr==8'h87 && doc_data==8'h40) r_fx_wtp++;
        if(doc_addr==8'hA6 && doc_data==8'h11) l_fx_halts++;
        if(doc_addr==8'hA7 && doc_data==8'h01) r_fx_halts++;
        if(doc_addr==8'hA6 && doc_data==8'h10) l_fx_run++;
        if(doc_addr==8'hA7 && doc_data==8'h00) r_fx_run++;
        if(doc_addr==8'h80) piano_wtp++;
        if(fx_l || fx_r) $fatal(1,"Prohibited whole-chip AY bypass");
    end

    task automatic ay_write(input bit right,input logic[3:0] regno,input logic[7:0] data);
        @(negedge clk);
        if(right) begin r_reg=regno;r_data=data;r_wr=1;end
        else begin l_reg=regno;l_data=data;l_wr=1;end
        @(negedge clk);
        l_wr=0;r_wr=0;
    endtask
    initial begin
        repeat(4) @(negedge clk);
        reset_n=1;sdram_ready=1;
        wait(ready);
        @(negedge clk);
        if (writes!==6528 || !dut.fx_bank_ready_r)
            $fatal(1,"FX bank incomplete, words=%0d",writes);
        $display("PASS: piano 1408 words, FX bank 5120 words, same SDRAM");

        // MCS-style tone+noise on left -> laser on DOC6.
        ay_write(0,4'd6,8'd20);
        ay_write(0,4'd7,8'h36);
        ay_write(0,4'd8,8'h0F);
        wait(l_fx_run>0);
        @(negedge clk);
        if(l_fx_wtp<1 || l_fx_halts<1)
            $fatal(1,"Left oscillator 6 did not play laser one-shot");
        if(fx6_count!==7 ||
           fx6_addrs[0]!==8'hA6 || fx6_data[0]!==8'h11 ||
           fx6_addrs[1]!==8'h86 || fx6_data[1]!==8'h50 ||
           fx6_addrs[2]!==8'hC6 || fx6_data[2]!==8'h18 ||
           fx6_addrs[3]!==8'h06 || fx6_data[3]!==8'h00 ||
           fx6_addrs[4]!==8'h26 || fx6_data[4]!==8'h3C ||
           fx6_addrs[5]!==8'h46 || fx6_data[5]!==8'd208 ||
           fx6_addrs[6]!==8'hA6 || fx6_data[6]!==8'h10)
            $fatal(1,"OSC6 initial one-shot command order or calibration wrong");
        if(piano_wtp<1) $fatal(1,"Existing piano voice lost");

        // Independent right-chip percussion -> kick on DOC7.
        ay_write(1,4'd6,8'd3);
        ay_write(1,4'd7,8'h2D);
        ay_write(1,4'd9,8'h0F);
        wait(r_fx_run>0);
        @(negedge clk);
        if(r_fx_wtp<1 || r_fx_halts<1)
            $fatal(1,"Right oscillator 7 did not play percussion one-shot");
        if(fx7_count!==7 ||
           fx7_addrs[0]!==8'hA7 || fx7_data[0]!==8'h01 ||
           fx7_addrs[1]!==8'h87 || fx7_data[1]!==8'h40 ||
           fx7_addrs[2]!==8'hC7 || fx7_data[2]!==8'h10 ||
           fx7_addrs[3]!==8'h07 || fx7_data[3]!==8'h00 ||
           fx7_addrs[4]!==8'h27 || fx7_data[4]!==8'h4D ||
           fx7_addrs[5]!==8'h47 || fx7_data[5]!==8'd208 ||
           fx7_addrs[6]!==8'hA7 || fx7_data[6]!==8'h00)
            $fatal(1,"OSC7 initial one-shot command order or calibration wrong");

        if(writes!==6528)
            $fatal(1,"FX command unexpectedly rewrote sample SDRAM");
        $display("PASS: OSC6 LEFT laser and OSC7 RIGHT kick with correct WTP and RUN");
        $display("PASS: whole-chip AY bypass disabled, piano oscillator scan intact");
        $finish;
    end
    initial begin
        #60000000;
        $fatal(1,"M6.5b timeout RAM=%0d FX6=%0d FX7=%0d",writes,l_fx_run,r_fx_run);
    end
endmodule
