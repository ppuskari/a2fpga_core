`timescale 1ns/1ps
module tb_ssi263_p8_chip;
  logic clk=0;
  always #5 clk=~clk;
  logic rst_n=0, xck=0,wr=0;
  logic [2:0] regno=0;
  logic [7:0] din=0;
  wire ar_n,powered;
  wire [5:0] phoneme;
  wire [7:0] r3;
  wire signed [15:0] pcm;
  integer changed=0;
  ssi263_p8_chip #(.LOGIC_HZ(160_000),.OUTPUT_HZ(16_000)) dut(
      .clk_i(clk),.reset_n_i(rst_n),.xck_tick_i(xck),
      .write_i(wr),.reg_i(regno),.data_i(din),
      .ar_n_o(ar_n),.powered_o(powered),
      .phoneme_o(phoneme),.r3_debug_o(r3),.pcm_o(pcm));
  always @(negedge clk) if (rst_n && powered && pcm!==0) changed=changed+1;
  task automatic cpu_write(input logic [2:0] r,input logic [7:0] v);
    @(negedge clk);wr=1;regno=r;din=v;
    @(negedge clk);wr=0;
  endtask
  initial begin
    repeat(8) @(negedge clk);rst_n=1;
    if(powered || !ar_n || r3!==8'h80)
      $fatal(1,"P8 chip reset/CTL status failed");
    cpu_write(3'd4,8'he8);
    cpu_write(3'd2,8'ha8);
    cpu_write(3'd1,8'h6f);
    cpu_write(3'd0,8'h60); // code L
    cpu_write(3'd3,8'h7f); // CTL falling, amplitude
    if(!powered || phoneme!=6'h20) $fatal(1,"P8 chip not powered");
    for(integer j=0;j<300000;j=j+1) begin
       @(negedge clk);xck=(j%2==0);
    end
    if(changed<100) $fatal(1,"P8 chip generated no sustained PCM: changed=%0d",changed);
    cpu_write(3'd3,8'h80);
    repeat(10) @(negedge clk);
    if(powered || !ar_n || pcm!==16'sd0)
      $fatal(1,"P8 power-down/IRQ/audio invalid");
    $display("PASS P8 chip register/R4 clock/5-section tract activity: nonzero samples %0d",changed);
    $finish;
  end
  initial begin #6000000;$fatal(1,"timeout");end
endmodule
