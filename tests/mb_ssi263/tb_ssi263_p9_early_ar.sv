`timescale 1ns/1ps
// P9 SSI263 stop release lookahead: independent full-chip register path.
// Normal A/R still occurs at phoneme end; stop b01 sends early A/R;
// next R0 is buffered until the *old* stop duration expires.
module tb_ssi263_p9_early_ar;
  logic clk=0;
  always #5 clk=~clk;
  logic rst_n=0,wr=0;
  logic [2:0] regno=0;
  logic [7:0] data=0;
  wire ar_n,powered,valid;
  wire [5:0] phoneme;
  wire [7:0] r3;
  wire signed [15:0] pcm;
  ssi263_p8_chip #(
      .LOGIC_HZ(1_000_000),.OUTPUT_HZ(16_000),
      .OUTPUT_FULL_FIR_ENABLE(0)
  ) dut (
      .clk_i(clk),.reset_n_i(rst_n),.xck_tick_i(1'b1),
      .write_i(wr),.reg_i(regno),.data_i(data),
      .ar_n_o(ar_n),.powered_o(powered),.phoneme_o(phoneme),
      .r3_debug_o(r3),.pcm_o(pcm),.sample_valid_o(valid)
  );
  task automatic write_reg(input [2:0] a,input [7:0] v);
     @(negedge clk);wr=1;regno=a;data=v;
     @(negedge clk);wr=0;
  endtask
  integer i;
  initial begin
     repeat(7) @(negedge clk);rst_n=1;
     write_reg(3'd4,8'he8);
     write_reg(3'd2,8'hf8); // frame duration 4096 XCK
     write_reg(3'd1,8'h60);
     write_reg(3'd0,8'he7); // stop code 0x27, duration 1 frame
     write_reg(3'd3,8'h7f);
     if(!powered||phoneme!==6'h27) $fatal(1,"stop setup");
     i=0;
     while(ar_n && i<4500)begin @(negedge clk);i++;end
     if(i>=4500) $fatal(1,"missing early A/R");
     if(dut.remain_xck_r==0 || dut.remain_xck_r>2000)
        $fatal(1,"early A/R outside stop release lookahead");
     write_reg(3'd0,8'hc8); // successor open vowel
     repeat(4) @(negedge clk);
     if(phoneme!==6'h27 || ar_n!==1'b1)
        $fatal(1,"early next R0 not held or A/R didn't clear");
     repeat(650) @(negedge clk);
     if(!dut.release_open_r)
        $fatal(1,"stop did not release into pending open vowel");
     if(phoneme!==6'h27)
        $fatal(1,"new phoneme applied before old stop expired");
     i=0;
     while(phoneme!==6'h08 && i<3000)begin @(negedge clk);i++;end
     if(i>=3000) $fatal(1,"pending phoneme not applied at stop end");
     if(dut.early_req_r || dut.pending_mask_r!=0 || !ar_n)
        $fatal(1,"early request state leaked into next phoneme");
     write_reg(3'd3,8'h80);
     repeat(10) @(negedge clk);
     if(powered||!ar_n) $fatal(1,"power-down state");
     $display("PASS: P9 SSI263 early A/R, queued writes, open-vowel release and timer continuity");
     $finish;
  end
  initial begin #1000000;$fatal(1,"timeout");end
endmodule
