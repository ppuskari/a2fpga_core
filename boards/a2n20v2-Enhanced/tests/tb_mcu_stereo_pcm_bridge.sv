// Standalone 44.1k MCU stereo PCM -> HDMI, no DOC instantiation.
// Test little-endian signed L/R, FIFO watermark, mute, underrun, reset.
module tb_mcu_stereo_pcm_bridge;
    reg clk=0,rst_n=0,atick=0,wr=0,rd=0;
    reg [23:0] addr=0,raddr=0;
    reg [7:0] data=0;
    wire rvalid;wire [7:0] rdata;
    wire signed [15:0] l,r;
    reg [15:0] meter_left=16'd26028, meter_right=16'd12345;
    reg [7:0] meter_clip=8'hA5;
    reg meter_valid=1;
    always #5 clk=~clk;
    mcu_stereo_pcm_bridge #(.PCM_AW(3),.START_WATERMARK(2)) dut (
        .clk(clk),.rst_n(rst_n),.audio_tick_pixel_i(atick),
        .spi_wr_i(wr),.spi_wr_addr_i(addr),.spi_wr_data_i(data),
        .spi_rd_i(rd),.spi_rd_addr_i(raddr),.spi_rd_valid_o(rvalid),
        .spi_rd_data_o(rdata),.pcm_left_o(l),.pcm_right_o(r),
        .hdmi_peak_left_i(meter_left),.hdmi_peak_right_i(meter_right),
        .hdmi_clip_history_i(meter_clip),.hdmi_diag_valid_i(meter_valid)
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
    task automatic read_meter(input [4:0] offset, output [7:0] got);
    begin
        @(negedge clk);rd=1;raddr=24'h800000|{19'd0,offset};
        @(negedge clk);if(!rvalid)begin
            $display("FAIL HDMI METER: registered read missing");$fatal(1);
        end
        got=rdata;rd=0;
    end endtask
    task automatic expect_meter(input [4:0] offset,input [7:0] expected);
    reg [7:0] got;
    begin
        read_meter(offset,got);
        if(got!==expected)begin
            $display("FAIL HDMI METER register %02h: %02h != %02h",
                     offset,got,expected);
            $fatal(1);
        end
    end endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        read_reg(0,value);
        if(value!==8'h50)begin $display("FAIL PCM: magic P");$fatal(1);end
        read_reg(1,value);
        if(value!==8'h43)begin $display("FAIL PCM: magic C");$fatal(1);end
        read_reg(2,value);
        if(value!==8'h01)begin $display("FAIL PCM: version");$fatal(1);end

        // First diagnostic read atomically snapshots all metering inputs.
        // A one-second update during this transfer may NOT tear the packet.
        expect_meter(5'h10,8'h48);
        meter_left=16'd20000;meter_clip=8'h00;
        expect_meter(5'h11,8'h4d);
        expect_meter(5'h12,8'h01);
        expect_meter(5'h13,8'ha5);
        expect_meter(5'h14,8'hac); // 26028 = 0x65AC
        expect_meter(5'h15,8'h65);
        expect_meter(5'h16,8'h39); // 12345 = 0x3039
        expect_meter(5'h17,8'h30);
        expect_meter(5'h18,8'h01);
        // Reaching first status block was harmless to its existing ABI.
        read_reg(0,value);
        if(value!==8'h50)begin $display("FAIL PCM v1 after HDMI diagnostic");$fatal(1);end
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
