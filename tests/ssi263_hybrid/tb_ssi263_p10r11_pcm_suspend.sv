`timescale 1ns/1ps
// R11: PCM suspend/resume must never count an intentional idle underrun,
// must keep the SSI event FIFO alive, and must re-prime without losing first
// samples. R6 legacy default/low-rate modes are tested separately.
module tb_ssi263_p10r11_pcm_suspend;
  reg clk=0;
  always #5 clk=~clk;
  reg rst_n=0,audio_tick=0,power=0;
  reg spi_wr=0,spi_rd=0,event_valid=0;
  reg [2:0] spi_wr_space=0,spi_rd_space=0,event_reg=0;
  reg [23:0] spi_wr_addr=0,spi_rd_addr=0;
  reg [7:0] spi_wr_data=0,event_data=0;
  wire spi_rd_valid;
  wire [7:0] spi_rd_data;
  wire signed [15:0] pcm;
  ssi263_hybrid_bridge #(.START_WATERMARK(4)) dut(
    .clk_i(clk),.reset_n_i(rst_n),.audio_tick_pixel_i(audio_tick),
    .speech_powered_i(power),.xck_tick_i(1'b0),
    .event_valid_i(event_valid),.event_reg_i(event_reg),
    .event_data_i(event_data),
    .spi_wr_i(spi_wr),.spi_wr_space_i(spi_wr_space),
    .spi_wr_addr_i(spi_wr_addr),.spi_wr_data_i(spi_wr_data),
    .spi_rd_i(spi_rd),.spi_rd_space_i(spi_rd_space),
    .spi_rd_addr_i(spi_rd_addr),.spi_rd_valid_o(spi_rd_valid),
    .spi_rd_data_o(spi_rd_data),.speech_pcm_o(pcm));

  task automatic wr(input [23:0] addr,input [7:0] val);
    @(negedge clk); spi_wr=1;spi_wr_space=4;spi_wr_addr=addr;spi_wr_data=val;
    @(negedge clk); spi_wr=0;
  endtask
  task automatic rd(input [23:0] addr,output [7:0] val);
    @(negedge clk);spi_rd=1;spi_rd_space=4;spi_rd_addr=addr;
    @(posedge clk);#1;
    if(!spi_rd_valid)$fatal(1,"R11 status read invalid");
    val=spi_rd_data;
    @(negedge clk);spi_rd=0;
  endtask
  task automatic sample_tick;
    @(negedge clk);audio_tick=1;
    repeat(4)@(negedge clk);audio_tick=0;
    repeat(4)@(negedge clk);
  endtask
  task automatic feed(input integer n, input [15:0] v);
    integer i;
    for(i=0;i<n;i=i+1)begin
      wr(2*i,v[7:0]);
      wr(2*i+1,v[15:8]);
    end
  endtask
  task automatic event_cpu(input [2:0] r, input [7:0] v);
    @(negedge clk);event_valid=1;event_reg=r;event_data=v;
    @(negedge clk);event_valid=0;
  endtask
  reg [7:0] d;
  integer i;
  initial begin
    repeat(6)@(negedge clk);rst_n=1;power=1;
    rd(24'h80001a,d);if(d!==8'hb7)$fatal(1,"R11 capability missing %h",d);
    rd(24'h80001b,d);if(d!==0)$fatal(1,"default must be resumed");
    wr(24'h800001,8'd1);
    feed(8,16'h1234);
    sample_tick();sample_tick();sample_tick();
    wr(24'h800002,8'd1);
    rd(24'h80001b,d);if(d!==1)$fatal(1,"suspend ACK missing");
    rd(24'h800004,d);if(d!==0)$fatal(1,"PCM FIFO not flushed by suspend");
    for(i=0;i<64;i=i+1)begin
      sample_tick();
      if(pcm !== 16'sd0)$fatal(1,"suspended PCM nonzero at tick %0d",i);
    end
    rd(24'h80000a,d);if(d!==0)$fatal(1,"suspension counted as underrun");
    event_cpu(3'd0,8'h60); // live Apple CPU write during suspension
    rd(24'h800008,d);if(d!==1)$fatal(1,"Apple SSI event lost while suspended");
    // Attempted stray PCM writes must not affect the queue until resumed.
    feed(2,16'h5678);
    rd(24'h800004,d);if(d!==0)$fatal(1,"suspended PCM accepted a write");
    wr(24'h800002,8'd0);
    rd(24'h80001b,d);if(d!==0)$fatal(1,"resume ACK missing");
    rd(24'h800004,d);if(d!==0)$fatal(1,"resume did not reinitialize FIFO");
    feed(8,16'h4321);
    sample_tick();
    if(pcm !== 16'sd0)$fatal(1,"resume played before watermark");
    sample_tick();
    sample_tick();
    if(pcm !== 16'sh4321)$fatal(1,"first resumed sample missing (%h)",pcm);
    rd(24'h80000a,d);if(d!==0)$fatal(1,"false UND after resume");
    rd(24'h800008,d);if(d!==1)$fatal(1,"event queue modified by PCM resume");
    // Powerdown always silences output as in R6, including the paused mode.
    wr(24'h800002,8'd1);
    @(negedge clk);power=0;
    repeat(3)@(negedge clk);
    if(pcm !== 0)$fatal(1,"powerdown failed to silence PCM");
    rd(24'h80000a,d);if(d!==0)$fatal(1,"false UND on powerdown");
    $display("PASS R11: explicit suspend ACK, no idle UND, event intact, first sample on resume");
    $finish;
  end
  initial begin #2000000;$fatal(1,"R11 simulation timeout");end
endmodule
