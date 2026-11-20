// P2AB: production DOC oscillator FSM with 15k.ntp's predominant
// type-2 header + type-7 optimized free-run sustain (instrument #1).
// P2Y previously tested only type-2 + type-3 nonideal IRQ/SWAP retarget.
// Both A and B have unique WTP/RTS: original A stops, B runs and loops.
module tb_p2ab_ideal_sustain;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg [2:0] div=0;
    wire clk_en=(div==0);
    always @(posedge clk) div<=div+1'b1;
    wire [15:0] wave_addr;
    wire wave_rd,wave_bank,ready;
    reg wave_ready=0;
    reg [7:0] wave_byte=8'h80;
    wire signed [15:0] l,r,m;
    doc5503 dut(
        .clk_i(clk),.reset_n_i(rst_n),.clk_en_i(clk_en),
        .ntp_loop_assist_i(1'b1),
        .cs_n_i(1'b1),.we_n_i(1'b1),.addr_i(8'h00),.data_i(8'h00),
        .data_o(),.wave_address_o(wave_addr),.wave_bank_o(wave_bank),
        .wave_rd_o(wave_rd),.wave_data_ready_i(wave_ready),
        .wave_data_i(wave_byte),.left_mix_o(l),.right_mix_o(r),
        .mono_mix_o(m),.ready_o(ready)
    );
    // Attack terminator, optimized sustain contains no zero terminator
    // and is expected to run continuously with CTRL mode FREE.
    always @(posedge clk) begin
        wave_ready<=wave_rd;
        if(wave_rd) wave_byte<=wave_addr[15:8]==8'h00 ? 8'h00 : 8'hB0;
    end
    reg seen_started=0;
    reg [23:0] sustain_acc_before=0;
    integer i;
    initial begin
        #30;rst_n=1;
        wait(ready);
        repeat(250) @(negedge clk);
        dut.osc_en_r=8'h3E;
        @(negedge clk);
        dut.fl_ram.osc_reg_r[0]=8'hA1;
        dut.fl_ram.osc_reg_r[1]=8'hA1;
        dut.fh_ram.osc_reg_r[0]=8'h00;
        dut.fh_ram.osc_reg_r[1]=8'h00;
        dut.vol_ram.osc_reg_r[0]=8'hC0;
        dut.vol_ram.osc_reg_r[1]=8'hC0;
        dut.wtp_ram.osc_reg_r[0]=8'h00; // terminated attack
        dut.wtp_ram.osc_reg_r[1]=8'h02; // B sustain
        dut.rts_ram.osc_reg_r[0]=8'h00;
        dut.rts_ram.osc_reg_r[1]=8'h09;
        dut.acc_ram.osc_reg_r[0]=24'h000000;
        dut.acc_ram.osc_reg_r[1]=24'h000000;
        dut.control_ram.osc_reg_r[0]=8'h16; // left+SWAP RUN
        dut.control_ram.osc_reg_r[1]=8'h11; // left+FREE HALT
        begin: wait_start
            for(i=0;i<40000;i=i+1) begin
                @(negedge clk);
                if(dut.control_ram.osc_reg_r[0]==8'h17 &&
                   dut.control_ram.osc_reg_r[1]==8'h10)begin
                    seen_started=1;
                    disable wait_start;
                end
            end
        end
        if(!seen_started)begin
            $display("FAIL P2AB ideal: A did not transfer to FREE B (A=%02x B=%02x)",
                dut.control_ram.osc_reg_r[0],
                dut.control_ram.osc_reg_r[1]);
            $fatal(1);
        end
        if(dut.wtp_ram.osc_reg_r[0]!=8'h00 ||
           dut.wtp_ram.osc_reg_r[1]!=8'h02 ||
           dut.rts_ram.osc_reg_r[1]!=8'h09)begin
            $display("FAIL P2AB ideal: altered original A/B DOC page and RTS");
            $fatal(1);
        end
        $display("PASS P2AB ideal: one-shot attack hands off to B FREE sustain");
        repeat(20000) @(negedge clk);
        sustain_acc_before=dut.acc_ram.osc_reg_r[1];
        repeat(20000) @(negedge clk);
        if(dut.control_ram.osc_reg_r[0]!=8'h17 ||
           dut.control_ram.osc_reg_r[1]!=8'h10 ||
           dut.acc_ram.osc_reg_r[1]==sustain_acc_before)begin
            $display("DBG B acc=%06x before=%06x A ctl=%02x B ctl=%02x",
                dut.acc_ram.osc_reg_r[1],sustain_acc_before,
                dut.control_ram.osc_reg_r[0],dut.control_ram.osc_reg_r[1]);
            $display("FAIL P2AB ideal: B FREE sustain stopped or froze");
            $fatal(1);
        end
        $display("PASS P2AB ideal: optimized 512-byte B waveform keeps running");
        $finish;
    end
    initial begin
        #10000000;
        $display("FAIL P2AB ideal: simulation timeout");
        $fatal(1);
    end
endmodule
