`timescale 1ns/1ps
// P10 SPI XFER spaces 4/5, actual HDMI sample tick, no lost CPU events.
module tb_ssi263_hybrid_bridge;
    logic clk=0;
    always #5 clk=~clk; // logic 54MHz abstracted (faster simulation)
    logic rst_n=0,audio_tick=0,power=0,xck=0;
    logic evt_valid=0;
    logic [2:0] evt_reg=0;
    logic [7:0] evt_data=0;
    logic spi_wr=0,spi_rd=0;
    logic [2:0] spi_wr_space=0,spi_rd_space=0;
    logic [23:0] spi_wr_addr=0,spi_rd_addr=0;
    logic [7:0] spi_wr_data=0;
    wire spi_rd_valid;
    wire [7:0] spi_rd_data;
    wire signed [15:0] pcm;

    ssi263_hybrid_bridge #(.START_WATERMARK(4)) dut (
        .clk_i(clk),.reset_n_i(rst_n),
        .audio_tick_pixel_i(audio_tick),.speech_powered_i(power),
        .xck_tick_i(xck),.event_valid_i(evt_valid),
        .event_reg_i(evt_reg),.event_data_i(evt_data),
        .spi_wr_i(spi_wr),.spi_wr_space_i(spi_wr_space),
        .spi_wr_addr_i(spi_wr_addr),.spi_wr_data_i(spi_wr_data),
        .spi_rd_i(spi_rd),.spi_rd_space_i(spi_rd_space),
        .spi_rd_addr_i(spi_rd_addr),.spi_rd_valid_o(spi_rd_valid),
        .spi_rd_data_o(spi_rd_data),.speech_pcm_o(pcm)
    );
    task automatic wr(input [2:0] space,input [23:0] addr,input [7:0] val);
      @(negedge clk);
      spi_wr=1;spi_wr_space=space;spi_wr_addr=addr;spi_wr_data=val;
      @(negedge clk);spi_wr=0;
    endtask
    task automatic rd(input [2:0] space,input [23:0] addr,
                       output [7:0] val);
      @(negedge clk);spi_rd=1;spi_rd_space=space;spi_rd_addr=addr;
      @(posedge clk);#1;
      if(!spi_rd_valid)$fatal(1,"SPI read didn't return valid");
      val=spi_rd_data;
      @(negedge clk);spi_rd=0;
    endtask
    task automatic event_send(input [2:0] a,input [7:0] d);
      @(negedge clk);
      evt_valid=1;evt_reg=a;evt_data=d;xck=1;
      @(negedge clk);evt_valid=0;xck=0;
    endtask
    task automatic sample_tick;
      @(negedge clk);audio_tick=1;
      repeat(4) @(negedge clk);audio_tick=0;
      repeat(4) @(negedge clk);
    endtask
    integer i;
    reg [7:0] v;
    initial begin
      repeat(6)@(negedge clk);rst_n=1;
      rd(3'd4,24'h800000,v);if(v!==8'h53)$fatal(1,"magic S");
      rd(3'd4,24'h800001,v);if(v!==8'h50)$fatal(1,"magic P");
      rd(3'd4,24'h800002,v);if(v!==8'd1)$fatal(1,"protocol version");
      if(pcm!==0)$fatal(1,"startup music isolation silence");
      event_send(3'd2,8'hA8);
      event_send(3'd0,8'h68);
      rd(3'd4,24'h800008,v);if(v!==2)$fatal(1,"two events missing");
      rd(3'd5,24'd0,v);if(v!==2)$fatal(1,"event0 register");
      rd(3'd5,24'd1,v);if(v!==8'hA8)$fatal(1,"event0 value");
      rd(3'd5,24'd2,v);if(v!==0)$fatal(1,"event0 seq");
      for(i=3;i<8;i++)rd(3'd5,i,v);
      rd(3'd5,24'd8,v);if(v!==0)$fatal(1,"event1 reg");
      rd(3'd5,24'd9,v);if(v!==8'h68)$fatal(1,"event1 val");
      rd(3'd5,24'd10,v);if(v!==1)$fatal(1,"event1 seq");
      for(i=11;i<16;i++)rd(3'd5,i,v);
      rd(3'd4,24'h800008,v);if(v!==0)$fatal(1,"events not popped");
      power=1;
      for(i=0;i<8;i++)begin
          wr(3'd4,2*i,(i+1));
          wr(3'd4,2*i+1,8'h12);
      end
      rd(3'd4,24'h800004,v);if(v!==8)$fatal(1,"8 PCM samples missing");
      sample_tick();sample_tick();
      if(pcm!==16'h1201)$fatal(1,"first audio frame %h",pcm);
      for(i=0;i<7;i++)sample_tick();
      if(pcm!==0)$fatal(1,"underrun did not mute");
      rd(3'd4,24'h80000A,v);if(v!==1)$fatal(1,"underrun not counted");
      wr(3'd4,24'h800000,8'h01);
      rd(3'd4,24'h800004,v);if(v!==0)$fatal(1,"PCM reset");
      rd(3'd4,24'h80000A,v);if(v!==0)$fatal(1,"reset underrun counter");
      if(pcm!==0)$fatal(1,"PCM reset did not mute");
      $display("PASS P10: timestamped SSI events, order/seq, real sample clock, PCM, underrun, reset and MCU-missing silence");
      $finish;
    end
    initial begin #3000000;$fatal(1,"P10 test timeout");end
endmodule
