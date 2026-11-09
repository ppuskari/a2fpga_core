`timescale 1ns/1ps
// P10-R6: old 44.1k mode, opt-in 22.05/11.025k source sample-hold,
// FPGA capability+rate ACK, FIFO counters and powerdown isolation.
module tb_ssi263_p10r6_multirate;
  logic clk=0;
  always #5 clk=~clk;
  logic rst_n=0,audio_tick=0,power=0;
  logic spi_wr=0,spi_rd=0;
  logic [2:0] spi_wr_space=0,spi_rd_space=0;
  logic [23:0] spi_wr_addr=0,spi_rd_addr=0;
  logic [7:0] spi_wr_data=0;
  wire spi_rd_valid;
  wire [7:0] spi_rd_data;
  wire signed [15:0] pcm;
  ssi263_hybrid_bridge #(.START_WATERMARK(4)) dut(
     .clk_i(clk),.reset_n_i(rst_n),.audio_tick_pixel_i(audio_tick),
     .speech_powered_i(power),.xck_tick_i(1'b0),
     .event_valid_i(1'b0),.event_reg_i(3'd0),.event_data_i(8'd0),
     .spi_wr_i(spi_wr),.spi_wr_space_i(spi_wr_space),
     .spi_wr_addr_i(spi_wr_addr),.spi_wr_data_i(spi_wr_data),
     .spi_rd_i(spi_rd),.spi_rd_space_i(spi_rd_space),
     .spi_rd_addr_i(spi_rd_addr),.spi_rd_valid_o(spi_rd_valid),
     .spi_rd_data_o(spi_rd_data),.speech_pcm_o(pcm));
  task automatic wr(input [23:0] addr,input [7:0] val);
    @(negedge clk);
    spi_wr=1;spi_wr_space=4;spi_wr_addr=addr;spi_wr_data=val;
    @(negedge clk);spi_wr=0;
  endtask
  task automatic rd(input [23:0] addr,output [7:0] val);
    @(negedge clk);spi_rd=1;spi_rd_space=4;spi_rd_addr=addr;
    @(posedge clk);#1;if(!spi_rd_valid)$fatal(1,"status invalid");
    val=spi_rd_data;
    @(negedge clk);spi_rd=0;
  endtask
  task automatic sample_tick;
    @(negedge clk);audio_tick=1;
    repeat(4) @(negedge clk);audio_tick=0;
    repeat(4) @(negedge clk);
  endtask
  task automatic feed8;
    integer j;
    for(j=0;j<8;j++)begin
      wr(2*j,(j+1));
      wr(2*j+1,8'h12);
    end
  endtask
  task automatic check_pcm(input [15:0] want);
    if(pcm!==want)$fatal(1,"PCM want=%04h got=%04h",want,pcm);
  endtask
  integer i;
  reg [7:0] v;
  initial begin
    repeat(6)@(negedge clk);rst_n=1;
    rd(24'h800002,v);if(v!==8'd1)$fatal(1,"legacy status version changed");
    rd(24'h800018,v);if(v!==8'hA6)$fatal(1,"R6 capability missing");
    rd(24'h800019,v);if(v!==8'd0)$fatal(1,"legacy 44k default missing");
    power=1;
    feed8();
    sample_tick();sample_tick();check_pcm(16'h1201);
    sample_tick();check_pcm(16'h1202); // legacy rate, every HDMI tick

    wr(24'h800001,8'd1); // enable 22.05k; atomically flush FIFO
    rd(24'h800019,v);if(v!==8'd1)$fatal(1,"22k rate ACK");
    rd(24'h800004,v);if(v!==0)$fatal(1,"22k rate change did not flush ring");
    check_pcm(0);
    feed8();
    sample_tick();check_pcm(0); // watermark arms playback
    sample_tick();check_pcm(0); // held phase
    sample_tick();check_pcm(16'h1201); // first 22k sample
    sample_tick();check_pcm(16'h1201); // held twice at HDMI 44k
    sample_tick();check_pcm(16'h1202);
    sample_tick();check_pcm(16'h1202);
    rd(24'h800004,v);if(v!==8'd6)$fatal(1,"22k FIFO consumption not halved (%0d)",v);
    rd(24'h80000A,v);if(v!==0)$fatal(1,"false underrun on hold tick");

    wr(24'h800001,8'd2); // enable 11.025k; flush again
    rd(24'h800019,v);if(v!==8'd2)$fatal(1,"11k rate ACK");
    feed8();
    for(i=0;i<4;i++)begin sample_tick();check_pcm(0);end
    sample_tick();check_pcm(16'h1201);
    for(i=0;i<3;i++)begin sample_tick();check_pcm(16'h1201);end
    sample_tick();check_pcm(16'h1202);
    rd(24'h800004,v);if(v!==8'd6)$fatal(1,"11k FIFO consumption not quartered (%0d)",v);

    wr(24'h800001,8'd3); // unsupported command ignored, no stream corruption
    rd(24'h800019,v);if(v!==8'd2)$fatal(1,"invalid rate changed mode");
    rd(24'h800004,v);if(v!==8'd6)$fatal(1,"invalid rate flushed ring");

    @(negedge clk);power=0;
    repeat(3)@(negedge clk);
    check_pcm(0);
    rd(24'h800004,v);if(v!==0)$fatal(1,"powerdown did not flush ring");
    wr(24'h800001,8'd0);
    rd(24'h800019,v);if(v!==0)$fatal(1,"return to legacy rate failed");
    $display("PASS P10-R6: 44k legacy, 22k double hold, 11k quadruple hold, rate ACK and reset");
    $finish;
  end
  initial begin #3000000;$fatal(1,"P10-R6 timeout");end
endmodule
