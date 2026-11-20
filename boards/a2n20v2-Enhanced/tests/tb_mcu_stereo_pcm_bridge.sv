// Standalone 44.1k MCU stereo PCM -> HDMI, no DOC instantiation.
// Test little-endian signed L/R, FIFO watermark, mute, underrun, reset.
module tb_mcu_stereo_pcm_bridge;
    reg clk=0,rst_n=0,atick=0,wr=0,rd=0;
    reg [23:0] addr=0,raddr=0;
    reg [7:0] data=0;
    wire rvalid;wire [7:0] rdata;
    wire signed [15:0] l,r;
    always #5 clk=~clk;
    mcu_stereo_pcm_bridge #(.PCM_AW(3),.START_WATERMARK(2)) dut (
        .clk(clk),.rst_n(rst_n),.audio_tick_pixel_i(atick),
        .spi_wr_i(wr),.spi_wr_addr_i(addr),.spi_wr_data_i(data),
        .spi_rd_i(rd),.spi_rd_addr_i(raddr),.spi_rd_valid_o(rvalid),
        .spi_rd_data_o(rdata),.pcm_left_o(l),.pcm_right_o(r)
    );
    task automatic write_byte(input [23:0] a,input [7:0] d);
    begin
        @(negedge clk);wr=1;addr=a;data=d;
        @(negedge clk);wr=0;
    end endtask
    task automatic write_frame(input [15:0] left,input [15:0] right);
    begin
        write_byte(24'd0,left[7:0]);
        write_byte(24'd1,left[15:8]);
        write_byte(24'd2,right[7:0]);
        write_byte(24'd3,right[15:8]);
    end endtask
    task automatic audio_tick;
    begin
        @(negedge clk);atick=1;
        @(negedge clk);atick=0;
        repeat(5) @(negedge clk);
    end endtask
    task automatic read_reg(input [3:0] idx,output [7:0] value);
    begin
        @(negedge clk);rd=1;raddr=24'h800000|{20'd0,idx};
        @(negedge clk);if(!rvalid)begin
            $display("FAIL PCM: no registered SPI read");$fatal(1);
        end
        value=rdata;rd=0;
    end endtask
    reg [7:0] value;
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        read_reg(0,value);
        if(value!==8'h50)begin $display("FAIL PCM: magic P");$fatal(1);end
        read_reg(1,value);
        if(value!==8'h43)begin $display("FAIL PCM: magic C");$fatal(1);end
        read_reg(2,value);
        if(value!==8'h01)begin $display("FAIL PCM: version");$fatal(1);end

        write_byte(24'h800001,8'h01); // enable
        write_frame(16'h1234,16'hfffe); // L positive R -2
        audio_tick();
        if(l!==16'h0000 || r!==16'h0000)begin
            $display("FAIL PCM: played before watermark");$fatal(1);end
        write_frame(16'h8765,16'h1357); // second frame
        audio_tick();
        if(l!==16'h1234 || r!==16'hfffe)begin
            $display("FAIL PCM: frame1 L=%04h R=%04h",l,r);$fatal(1);end
        audio_tick();
        if(l!==16'h8765 || r!==16'h1357)begin
            $display("FAIL PCM: frame2 L=%04h R=%04h",l,r);$fatal(1);end
        audio_tick();
        if(l!==16'h0000 || r!==16'h0000 || dut.underruns_r!==16'd1)begin
            $display("FAIL PCM: underrun must mute and count once");$fatal(1);end
        $display("PASS PCM HDMI: signed 16-bit L/R order and watermark/underrun");

        write_frame(16'h3333,16'h4444);
        write_frame(16'h5555,16'h6666);
        audio_tick();
        if(l!==16'h3333 || r!==16'h4444)begin
            $display("FAIL PCM: underrun recovery");$fatal(1);end
        write_byte(24'h800001,8'h00);
        audio_tick();
        if(l!==0 || r!==0)begin
            $display("FAIL PCM: mute failed");$fatal(1);end
        write_byte(24'h800000,8'hA5);
        read_reg(8,value);
        if(value!==0 || dut.wrptr_r!=0 || dut.rdptr_r!=0)begin
            $display("FAIL PCM: reset did not clear counter/FIFO");$fatal(1);end
        $display("PASS PCM HDMI: restart after underrun, mute, hard reset");
        $finish;
    end
    initial begin #1000000;$display("FAIL PCM: timeout");$fatal(1);end
endmodule
