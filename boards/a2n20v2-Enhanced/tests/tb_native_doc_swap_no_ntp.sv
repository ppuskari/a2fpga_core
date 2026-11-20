// Golden native IIgs / August DOC SWAP sequence without any NTP link.
// Actual DOC oscillator FSM must start the partner and leave native
// waveform pointers & resolution untouched. MCU PCM is entirely separate.
module tb_native_doc_swap_no_ntp;
reg clk=0,reset_n=0;
always #5 clk=~clk;
reg [2:0] div=0;
wire clk_en=(div==0);
always @(posedge clk)div<=div+1'b1;
wire [15:0] wave_addr;
wire wave_bank,wave_rd,ready;
reg wave_ready=0;
reg [7:0] wave_byte=8'h80;
wire signed [15:0] left_mix,right_mix,mono_mix;
doc5503 dut(
    .clk_i(clk),.reset_n_i(reset_n),.clk_en_i(clk_en),
    .cs_n_i(1'b1),.we_n_i(1'b1),.addr_i(8'h00),.data_i(8'h00),
    .data_o(),.wave_address_o(wave_addr),.wave_bank_o(wave_bank),
    .wave_rd_o(wave_rd),.wave_data_ready_i(wave_ready),
    .wave_data_i(wave_byte),.left_mix_o(left_mix),
    .right_mix_o(right_mix),.mono_mix_o(mono_mix),.ready_o(ready)
);
always @(posedge clk)begin
    wave_ready<=wave_rd;
    if(wave_rd)wave_byte<=(wave_addr<16'h0100)?8'h00:8'h80;
end
integer i;
reg seen_partner=0;
initial begin
    #30;reset_n=1;
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
    dut.wtp_ram.osc_reg_r[0]=8'h00;
    dut.wtp_ram.osc_reg_r[1]=8'h02;
    dut.rts_ram.osc_reg_r[0]=8'h00;
    dut.rts_ram.osc_reg_r[1]=8'h09;
    dut.acc_ram.osc_reg_r[0]=24'h0;
    dut.acc_ram.osc_reg_r[1]=24'h0;
    dut.control_ram.osc_reg_r[0]=8'h16; // left A SWAP RUN
    dut.control_ram.osc_reg_r[1]=8'h17; // left B SWAP HALT
    begin: watch
        for(i=0;i<30000;i=i+1)begin
            @(negedge clk);
            if(dut.control_ram.osc_reg_r[0]==8'h17 &&
               dut.control_ram.osc_reg_r[1]==8'h16)begin
                seen_partner=1;
                disable watch;
            end
        end
    end
    if(!seen_partner)begin
        $display("FAIL DOC: normal A-SWAP did not launch B-SWAP");
        $fatal(1);
    end
    if(dut.wtp_ram.osc_reg_r[0]!==8'h00 ||
       dut.wtp_ram.osc_reg_r[1]!==8'h02 ||
       dut.rts_ram.osc_reg_r[0]!==8'h00 ||
       dut.rts_ram.osc_reg_r[1]!==8'h09)begin
        $display("FAIL DOC: ordinary SWAP modified native WTP/RTS");
        $fatal(1);
    end
    $display("PASS DOC native: August SWAP A halt/B start, no NTP assist");
    $finish;
end
initial begin #5000000;$display("FAIL DOC: simulation timeout");$fatal(1);end
endmodule
