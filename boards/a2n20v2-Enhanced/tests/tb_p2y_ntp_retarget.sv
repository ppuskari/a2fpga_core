// P2Y: real DOC oscillator FSM, not a stand-alone model of loop behavior.
// Nonideal NTP A(IRQ|SWAP) -> B(SWAP) -> A sustain retarget.
// Verifies P2U/standard DOC SWAP is UNCHANGED when gate is deasserted.
module tb_p2y_ntp_retarget;
    reg clk=0,reset_n=0;
    always #5 clk=~clk; // 100 MHz simulation; clock-rate ratio modeled below
    reg [2:0] divider=0;
    wire clk_en=(divider==0);
    always @(posedge clk) divider<=divider+1'b1;
    reg ntp_assist=0;
    wire [15:0] wave_addr;
    wire wave_bank, wave_rd;
    reg wave_ready=0;
    reg [7:0] wave_byte=8'h80;
    wire ready;
    wire signed [15:0] left_mix,right_mix,mono_mix;

    doc5503 dut (
        .clk_i(clk),.reset_n_i(reset_n),.clk_en_i(clk_en),
        .ntp_loop_assist_i(ntp_assist),
        .cs_n_i(1'b1),.we_n_i(1'b1),.addr_i(8'h00),.data_i(8'h00),
        .data_o(),.wave_address_o(wave_addr),.wave_bank_o(wave_bank),
        .wave_rd_o(wave_rd),.wave_data_ready_i(wave_ready),
        .wave_data_i(wave_byte),.left_mix_o(left_mix),
        .right_mix_o(right_mix),.mono_mix_o(mono_mix),
        .ready_o(ready)
    );
    // Attack is the first DOC page and terminates immediately on $00.
    // Sustain is at $0200, filled with $80 (no terminator), so we can
    // inspect A's retarget before B completes its first loop.
    always @(posedge clk) begin
        wave_ready <= wave_rd;
        if(wave_rd) wave_byte <= (wave_addr<16'h0100) ? 8'h00 : 8'h80;
    end
    task automatic setup_pair;
    begin
        // Resetting to idle/halting both mirrors the tracker note-start.
        dut.fl_ram.osc_reg_r[0]=8'hA1;
        dut.fl_ram.osc_reg_r[1]=8'hA1;
        dut.fh_ram.osc_reg_r[0]=8'h00;
        dut.fh_ram.osc_reg_r[1]=8'h00;
        dut.vol_ram.osc_reg_r[0]=8'hC0;
        dut.vol_ram.osc_reg_r[1]=8'hC0;
        dut.wtp_ram.osc_reg_r[0]=8'h00;  // attack, DOC page zero
        dut.wtp_ram.osc_reg_r[1]=8'h02;  // sustain
        dut.rts_ram.osc_reg_r[0]=8'h00;
        dut.rts_ram.osc_reg_r[1]=8'h09;
        dut.acc_ram.osc_reg_r[0]=24'h0;
        dut.acc_ram.osc_reg_r[1]=24'h0;
        dut.control_ram.osc_reg_r[0]=8'h1E; // L, IRQ, SWAP, running
        dut.control_ram.osc_reg_r[1]=8'h17; // L, SWAP, HALT
    end
    endtask
    initial begin
        #30;reset_n=1;
        wait(ready);
        repeat(250) @(negedge clk); // let reset/register sweep settle
        dut.osc_en_r=8'h3E; // standard 32-oscillator DOC timing

        ntp_assist=0;
        @(negedge clk);setup_pair();
        repeat(15000) @(negedge clk);
        if(dut.wtp_ram.osc_reg_r[0]!==8'h00 ||
           dut.rts_ram.osc_reg_r[0]!==8'h00)begin
            $display("FAIL P2Y HDL: standard SWAP unexpectedly retargeted");
            $fatal(1);
        end
        $display("PASS P2Y HDL: NTP assist disabled preserves normal DOC SWAP");

        ntp_assist=1;
        @(negedge clk);setup_pair();
        begin: wait_for_retarget
            integer i;
            for(i=0;i<25000;i=i+1)begin
                @(negedge clk);
                if(dut.wtp_ram.osc_reg_r[0]===8'h02 &&
                   dut.rts_ram.osc_reg_r[0]===8'h09 &&
                   dut.control_ram.osc_reg_r[0]===8'h17)
                    disable wait_for_retarget;
            end
            $display("DBG P2Y A ctl=%02x WTP=%02x RTS=%02x B ctl=%02x WTP=%02x RTS=%02x",dut.control_ram.osc_reg_r[0],dut.wtp_ram.osc_reg_r[0],dut.rts_ram.osc_reg_r[0],dut.control_ram.osc_reg_r[1],dut.wtp_ram.osc_reg_r[1],dut.rts_ram.osc_reg_r[1]);
            $display("DBG P2Y currOsc=%d state=%d haltEvent=%02x fetchAddr=%04x enable=%02x",dut.curr_osc_r,dut.osc_state_r,dut.debug_halt_event_r,wave_addr,dut.osc_en_r);
            $display("FAIL P2Y HDL: no hardware first-end retarget");
            $fatal(1);
        end
        if(dut.wtp_ram.osc_reg_r[1]!==8'h02 ||
           dut.rts_ram.osc_reg_r[1]!==8'h09)begin
            $display("FAIL P2Y HDL: sustain partner was corrupted");
            $fatal(1);
        end
        $display("PASS P2Y HDL: first-end A retargets to B, IRQ cleared, SWAP retained");
        $finish;
    end
    initial begin
        #5000000; $display("FAIL P2Y HDL: global simulation timeout");$fatal(1);
    end
endmodule
