// M6.4.1 coherent AY->DOC publication regression.
// Synthetic AY register data, but MCS's real $86C8 write order:
// R0..R14, left followed by right for each index.
// No original software or song tables are embedded.
`timescale 1ns/1ps
module tb_mb_doc_publish;
    parameter integer TEST_RES=0;
    logic clk=0;
    always #5 clk=~clk;
    logic reset_n=0, sdram_ready=0;
    logic l_wr=0, r_wr=0;
    logic [3:0] l_reg=0, r_reg=0;
    logic [7:0] l_data=0, r_data=0;
    logic l_psg_reset_n=1, r_psg_reset_n=1;
    logic ram_ready=0;
    wire ram_wr, doc_wr, ready, fx_l, fx_r;
    wire [7:0] doc_addr, doc_data;
    wire [20:0] ram_addr;
    wire [31:0] ram_data;
    wire [3:0] ram_byte_en;
    wire [2:0] active_voice;

    mb_doc_bridge #(
        .HOST_SPACING_CYCLES(16),
        .SCAN_PAUSE_CYCLES(64),
        .SUSTAIN_RES(3'(TEST_RES)),
        .DECLICK_ENABLE(1'b1),
        .FX_AY_BYPASS_ENABLE(1'b0),
        .COHERENT_PUBLISH_ENABLE(1'b1),
        // Interleaved MCS registers here are ~500 clocks apart.
        // No inter-register gap may publish a partial snapshot.
        .COHERENT_IDLE_CYCLES(1200)
    ) dut (
        .clk_i(clk),.reset_n_i(reset_n),.sdram_ready_i(sdram_ready),
        .ay_l_wr_i(l_wr),.ay_l_reg_i(l_reg),.ay_l_data_i(l_data),
        .ay_r_wr_i(r_wr),.ay_r_reg_i(r_reg),.ay_r_data_i(r_data),
        .ay_l_env_level_i(5'd31),.ay_r_env_level_i(5'd31),
        .ay_l_reset_n_i(l_psg_reset_n),.ay_r_reset_n_i(r_psg_reset_n),
        .doc_wr_o(doc_wr),.doc_addr_o(doc_addr),.doc_data_o(doc_data),
        .ram_wr_o(ram_wr),.ram_addr_o(ram_addr),
        .ram_data_o(ram_data),.ram_byte_en_o(ram_byte_en),
        .ram_ready_i(ram_ready),.ready_o(ready),
        .active_voice_o(active_voice),.fx_ay_l_o(fx_l),.fx_ay_r_o(fx_r)
    );

    integer ram_count=0, ram_delay=0;
    logic ram_busy=0, prev_ram_wr=0;
    always @(posedge clk) begin
        ram_ready<=0;
        if (!reset_n) begin
            ram_busy<=0; prev_ram_wr<=0; ram_count<=0;
        end else begin
            prev_ram_wr<=ram_wr;
            if(ram_wr && !prev_ram_wr) begin
                if(ram_busy || ram_count>=1408 || ram_addr!==ram_count ||
                   ram_byte_en!==4'hF)
                    $fatal(1,"Bad piano preload word=%0d addr=%0d",ram_count,ram_addr);
                ram_count<=ram_count+1;
                ram_busy<=1;
                ram_delay<=2;
            end
            if(ram_busy) begin
                if(ram_delay==0) begin ram_ready<=1;ram_busy<=0;end
                else ram_delay<=ram_delay-1;
            end
        end
    end

    logic [7:0] mcs_l[0:14],mcs_r[0:14];
    integer vol_left=0,vol_right=0,halt_count=0,wtp_count=0,cycles=0;
    // Detect any abrupt active-note HALT after initial setup.
    always @(posedge clk) if(reset_n) begin
        cycles<=cycles+1;
        if(doc_wr) begin
            if(doc_addr==8'h40) vol_left=int'(doc_data);
            if(doc_addr==8'h43) vol_right=int'(doc_data);
            if(doc_addr==8'h80) wtp_count++;
            if(doc_addr==8'hA0 && doc_data[0]) begin
                halt_count++;
                if(vol_left!=0)
                    $fatal(1,"DOC0 HALT while volume=%0d",vol_left);
            end
        end
    end

    task automatic write_ay(input bit ch,input logic [3:0] addr,
                            input logic [7:0] value);
        @(negedge clk);
        if(ch)begin r_reg=addr;r_data=value;r_wr=1;end
        else begin l_reg=addr;l_data=value;l_wr=1;end
        @(negedge clk);
        l_wr=0;r_wr=0;
    endtask

    // Real MCS order: 0..14, interleaved L/R. With 500 intervening
    // clocks, the DOC voice scanner visits each oscillator repeatedly.
    task automatic mcs_frame(input bit require_atomic);
        logic [7:0] old_l0,old_r0,old_l1;
        old_l0=dut.doc_regs[0][0];
        old_l1=dut.doc_regs[0][1];
        old_r0=dut.doc_regs[1][0];
        for(integer idx=0;idx<15;idx++) begin
            write_ay(0,4'(idx),mcs_l[idx]);
            write_ay(1,4'(idx),mcs_r[idx]);
            if(require_atomic && idx<14) begin
                if(dut.doc_regs[0][0]!==old_l0 ||
                   dut.doc_regs[0][1]!==old_l1 ||
                   dut.doc_regs[1][0]!==old_r0)
                    $fatal(1,"DOC published an intermediate R%0d snapshot",idx);
            end
            repeat(500) @(negedge clk);
        end
        if(dut.doc_regs[0][0]!==mcs_l[0] ||
           dut.doc_regs[0][1]!==mcs_l[1] ||
           dut.doc_regs[1][0]!==mcs_r[0] ||
           dut.doc_regs[0][8]!==mcs_l[8] ||
           dut.doc_regs[1][8]!==mcs_r[8])
            $fatal(1,"Frame not coherently published after R14");
    endtask

    initial begin
        for(integer i=0;i<15;i++)begin mcs_l[i]=0;mcs_r[i]=0;end
        // Both AY chips use tone A with nonzero fixed volume.
        mcs_l[0]=8'hF0;mcs_l[1]=8'h01;
        mcs_r[0]=8'h90;mcs_r[1]=8'h00;
        mcs_l[7]=8'h3E;mcs_r[7]=8'h3E;
        mcs_l[8]=8'h0F;mcs_r[8]=8'h0F;
        repeat(6) @(negedge clk);
        reset_n=1;
        sdram_ready=1;
        mcs_frame(1);
        wait(ready && vol_left>=64 && vol_right>=64);
        @(negedge clk);
        $display("PASS: initial interleaved 15-register MCS frame commits coherently");

        // Exactly the known hazardous low/high change:
        // $01F0 -> intermediate $0120 -> final $0220.
        // The middle pitch would otherwise force a false piano re-strike.
        mcs_l[0]=8'h20;mcs_l[1]=8'h02;
        mcs_r[0]=8'h60;mcs_r[1]=8'h00;
        mcs_frame(1);
        if({dut.doc_regs[0][1],dut.doc_regs[0][0]}!==16'h0220)
            $fatal(1,"DOC did not receive final pitch");
        $display("PASS: split AY period bytes invisible to the DOC voice scanner");

        // Simulate song-end ($873D/$871E): both active amplitudes go
        // to zero together, without asserting the PSG reset line.
        mcs_l[8]=0;mcs_r[8]=0;
        mcs_frame(1);
        wait(vol_left==0 && vol_right==0);
        repeat(3000) @(negedge clk);
        if(dut.doc_regs[0][8]!==0 || dut.doc_regs[1][8]!==0)
            $fatal(1,"Song-end amplitudes did not publish");
        $display("PASS: MCS rewind uses coherent stereo note-off, no hardware PSG reset");

        // Next repeat starts after four software timer ticks: the
        // stage must not leave stale registers or block new notes.
        mcs_l[0]=8'hF0;mcs_l[1]=8'h01;mcs_l[8]=8'h0F;
        mcs_r[0]=8'h90;mcs_r[1]=8'h00;mcs_r[8]=8'h0F;
        mcs_frame(1);
        wait(vol_left>=64 && vol_right>=64);
        $display("PASS: next repeated phrase re-strikes both piano voices");

        // Fallback: standalone software writes only R0 and R1.
        // They must publish together after an idle window, not after
        // the first byte. Other registers remain unchanged.
        write_ay(0,4'd0,8'h30);
        repeat(400) @(negedge clk);
        if(dut.doc_regs[0][0]!==8'hF0)
            $fatal(1,"Fallback published partial tone low");
        write_ay(0,4'd1,8'h03);
        repeat(700) @(negedge clk);
        if(dut.doc_regs[0][0]!==8'hF0 ||
           dut.doc_regs[0][1]!==8'h01)
            $fatal(1,"Fallback published before idle");
        repeat(550) @(negedge clk);
        if({dut.doc_regs[0][1],dut.doc_regs[0][0]}!==16'h0330)
            $fatal(1,"Fallback did not publish paired writes");
        if(dut.doc_regs[1][0]!==8'h90)
            $fatal(1,"Left-only fallback changed right chip");
        $display("PASS: non-MCS low/high pair and independent chip idle fallback");

        // A partial 0..14 frame must never starve future updates.
        write_ay(0,4'd0,8'h40);
        write_ay(0,4'd1,8'h02);
        write_ay(0,4'd2,8'h12);
        repeat(1300) @(negedge clk);
        if(dut.doc_regs[0][2]!==8'h12 ||
           dut.doc_regs[0][0]!==8'h40)
            $fatal(1,"Aborted frame did not flush via idle fallback");
        $display("PASS: aborted MCS sequence cannot indefinitely block publication");

        // Preserve immediate PB2 reset semantics for game software.
        @(negedge clk);
        l_psg_reset_n=0;
        repeat(3) @(negedge clk);
        if(dut.doc_regs[0][0]!==0 || dut.doc_regs[0][8]!==0 ||
           dut.doc_regs[1][0]!==8'h90)
            $fatal(1,"PSG reset did not clear only its own channel");
        l_psg_reset_n=1;
        $display("PASS: per-chip PSG reset cancels pending publication");
        $display("PASS: M6.4.1 coherent DOC publication RES=%0d",TEST_RES);
        $finish;
    end

    initial begin
        #30000000;
        $fatal(1,"M6.4.1 timeout, piano=%0d, DOC left vol=%0d, right=%0d",
               ram_count,vol_left,vol_right);
    end
endmodule
