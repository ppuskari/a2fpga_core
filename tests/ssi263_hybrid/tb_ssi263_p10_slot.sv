`timescale 1ns/1ps
// The P10 configuration excludes P8/P9 DSP even if FULL_CHIP_ENABLE=1.
// Right VIA CA1 and SSI bus timing are independent of the MCU PCM stream.
module tb_ssi263_p10_slot;
  logic clk=0;
  always #5 clk=~clk;
  logic rst_n=0,enabled=1,select=1,xck=0,stb=0,rw_n=1;
  logic [7:0] addr=8'h40,data=0;
  wire selected,read_en,via_ca1,powered;
  wire [7:0] read_data;
  wire [5:0] phoneme;
  wire signed [15:0] pcm;
  wire evt_valid,evt_xck,evt_power;
  wire [2:0] evt_reg;
  wire [7:0] evt_data;
  integer events=0;
  ssi263_slot #(.HYBRID_ENABLE(1),.FULL_CHIP_ENABLE(1)) dut (
    .clk_i(clk),.reset_n_i(rst_n),.enabled_i(enabled),
    .card_io_sel_i(select),.xck_tick_i(xck),
    .data_in_strobe_i(stb),.rw_n_i(rw_n),
    .card_addr_i(addr),.data_i(data),
    .speech_selected_o(selected),.speech_read_o(read_en),
    .speech_data_o(read_data),.via_ca1_o(via_ca1),
    .powered_o(powered),.phoneme_o(phoneme),.speech_pcm_o(pcm),
    .hybrid_pcm_i(16'sh1267),
    .hybrid_event_valid_o(evt_valid),
    .hybrid_event_reg_o(evt_reg),
    .hybrid_event_data_o(evt_data),
    .hybrid_xck_tick_o(evt_xck),.hybrid_powered_o(evt_power)
  );
  always @(posedge clk)begin
      if(evt_valid)begin
          events<=events+1;
          if(evt_reg>4)$fatal(1,"SSI event register invalid");
      end
  end
  task automatic wr(input [7:0] a,input [7:0] d);
     @(negedge clk);addr=a;data=d;rw_n=0;stb=1;
     repeat(3) @(negedge clk);
     stb=0;rw_n=1;repeat(3)@(negedge clk);
  endtask
  integer i;
  initial begin
    repeat(6)@(negedge clk);rst_n=1;
    wr(8'h42,8'hf8); // rate=15, 4096 XCK ticks/frame
    wr(8'h40,8'he8); // mode=3, duration=1 frame
    wr(8'h43,8'h7f); // R3 power on, volume=15
    if(!powered || !evt_power || pcm!==16'sh1267)
      $fatal(1,"P10 chip not powered or hybrid audio gate");
    for(i=0;i<4097;i++)begin
       @(negedge clk);xck=1;
       @(negedge clk);xck=0;
    end
    repeat(3)@(negedge clk);
    if(via_ca1!==0)$fatal(1,"FPGA SSI A/R not asserted at elapsed timer");
    if(events!==3)$fatal(1,"CPU writes not preserved: %0d",events);
    wr(8'h43,8'h80); // physical powerdown
    if(powered || via_ca1!==1 || pcm!==0)
       $fatal(1,"MCU silence/fault isolation failed on powerdown");
    if(events!==4)$fatal(1,"Powerdown event missing");
    $display("PASS P10: Apple SSI write ordering, FPGA CA1 timing, MCU PCM gate and powerdown");
    $finish;
  end
  initial begin #1000000;$fatal(1,"SSI slot timeout");end
endmodule
