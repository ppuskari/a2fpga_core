// M1 slot-3 ROMless register ABI and independent XFER7 byte FIFO.
module tb_media_mailbox_slot3;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg asel=0,arw=1,astrobe=0,sw=0,sr=0;
    reg [3:0] areg=0;
    reg [7:0] adata=0,sdata=0;
    reg [23:0] sa=0,ra=0;
    wire avalid,svalid;
    wire [7:0] ardata,srdata;
    media_mailbox_slot3 #(.FIFO_AW(3)) dut(
        .clk(clk),.rst_n(rst_n),
        .apple_sel_i(asel),.apple_rw_n_i(arw),
        .apple_write_strobe_i(astrobe),
        .apple_reg_i(areg),.apple_wdata_i(adata),
        .apple_read_o(avalid),.apple_rdata_o(ardata),
        .spi_wr_i(sw),.spi_wr_addr_i(sa),.spi_wr_data_i(sdata),
        .spi_rd_i(sr),.spi_rd_addr_i(ra),
        .spi_rd_valid_o(svalid),.spi_rd_data_o(srdata)
    );
    task automatic apple_read(input [3:0] off,output [7:0] val);
    begin
        @(negedge clk);asel=1;arw=1;areg=off;
        #1;
        if(!avalid)begin $display("FAIL M1: no Apple bus read select");$fatal(1);end
        val=ardata;
        @(negedge clk);asel=0;
        repeat(2) @(negedge clk);
    end endtask
    task automatic apple_write(input [3:0] off,input [7:0] val);
    begin
        @(negedge clk);asel=1;arw=0;areg=off;adata=val;astrobe=1;
        @(negedge clk);astrobe=0;asel=0;arw=1;
        repeat(2) @(negedge clk);
    end endtask
    task automatic spi_write(input [23:0] addr,input [7:0] val);
    begin
        @(negedge clk);sw=1;sa=addr;sdata=val;
        @(negedge clk);sw=0;
        repeat(2) @(negedge clk);
    end endtask
    task automatic spi_read(input [23:0] addr,output [7:0] val);
    begin
        @(negedge clk);sr=1;ra=addr;
        @(negedge clk);if(!svalid)begin $display("FAIL M1: SPI read handshake");$fatal(1);end
        val=srdata;sr=0;
        repeat(2) @(negedge clk);
    end endtask
    reg [7:0] v;
    integer j;
    initial begin
        repeat(4) @(negedge clk);rst_n=1;

        apple_read(0,v);if(v!==8'h4d)$fatal(1,"M1: M magic");
        apple_read(1,v);if(v!==8'h42)$fatal(1,"M1: B magic");
        apple_read(2,v);if(v!==8'h01)$fatal(1,"M1: protocol");
        apple_read(15,v);if(v!==8'ha5)$fatal(1,"M1: marker");
        apple_read(3,v);if(v!==8'h02)$fatal(1,"M1: initial FREE status");
        spi_read(24'h800012,v);if(v==8'hff)$fatal(1,"M1: SPI status");
        spi_write(24'h800012,8'h01); // MCU ready
        apple_read(3,v);if(v!==8'h03)$fatal(1,"M1: ready bit");

        apple_write(8,8'h03); // expected diagnostic upload: 3
        apple_write(9,8'h00);
        apple_write(10,8'h00);
        apple_write(11,8'h00);
        spi_read(24'h800016,v);if(v!==8'h03)$fatal(1,"M1: expected size");

        apple_write(4,8'h01); // PING, sequence 1
        apple_read(3,v);if((v & 8'h04)==0)$fatal(1,"M1: no pending");
        apple_read(10,v);if(v!==8'h01)$fatal(1,"M1: seq increment");
        spi_read(24'h800010,v);if(v!==8'h01)$fatal(1,"M1: SPI cmd");
        apple_write(4,8'h03); // should reject, not overwrite
        apple_read(3,v);if((v & 8'h40)==0)$fatal(1,"M1: no busy-reject bit");
        spi_write(24'h800010,8'h00); // wrong ack
        apple_read(3,v);if((v & 8'h04)==0)$fatal(1,"M1: mismatched ack cleared");
        spi_write(24'h800011,8'hA5); // result
        spi_write(24'h800010,8'h01); // matching ack
        apple_read(3,v);if((v & 8'h04)!=0)$fatal(1,"M1: command not cleared");
        apple_read(11,v);if(v!==8'h01)$fatal(1,"M1: ack sequence");
        apple_read(12,v);if(v!==8'hA5)$fatal(1,"M1: result");

        apple_write(5,8'h11);
        apple_write(5,8'h22);
        apple_write(5,8'h33);
        apple_read(8,v);
        if(v!==8'd3)begin
            $display("M1 DEBUG FIFO: read=%h count=%0d wrptr=%0d rdptr=%0d applewr=%0d",v,dut.count_w,dut.wrptr_r,dut.rdptr_r,dut.apple_writes_r);
            $fatal(1,"M1: fifo count 3");
        end
        spi_read(24'h000000,v);if(v!==8'h11)$fatal(1,"M1: FIFO byte1");
        spi_read(24'h000001,v);if(v!==8'h22)$fatal(1,"M1: FIFO byte2");
        spi_read(24'h000002,v);if(v!==8'h33)$fatal(1,"M1: FIFO byte3");
        apple_read(8,v);if(v!==8'd0)$fatal(1,"M1: FIFO drained");

        for(j=0;j<8;j=j+1)apple_write(5,8'(j));
        apple_read(6,v);if(v!==8'h00)$fatal(1,"M1: FIFO must be full");
        apple_write(5,8'hAA); // rejected: overflow counter
        apple_read(13,v);if(v!==8'h01)$fatal(1,"M1: no FIFO overflow");
        spi_write(24'h800013,8'hA5);
        apple_read(8,v);if(v!==8'd0)$fatal(1,"M1: FIFO reset");
        apple_read(13,v);if(v!==8'd0)$fatal(1,"M1: overflow reset");

        spi_write(24'h800020,8'h10); // MCU loopback inject BEGIN
        spi_read(24'h800010,v);if(v!==8'h10)$fatal(1,"M1: loopback cmd");
        apple_read(10,v);if(v!==8'h02)$fatal(1,"M1: loopback seq");
        spi_write(24'h800021,8'h5A);
        spi_read(24'h000000,v);if(v!==8'h5A)$fatal(1,"M1: loopback FIFO");
        spi_write(24'h800010,8'h02);
        apple_read(3,v);if(v & 8'h04)$fatal(1,"M1: loopback ack");
        spi_read(24'h800014,v);if(v==8'h00)$fatal(1,"M1: Apple writes not counted");
        spi_read(24'h800012,v);if(v==8'h00)$fatal(1,"M1: Apple reads not counted");

        $display("PASS M1 slot3: ROMless ID/ready, command sequence/reject/ACK");
        $display("PASS M1 slot3: Apple-to-MCU FIFO, full/overflow/reset");
        $display("PASS M1 slot3: MCU console injection, counters, test length");
        $finish;
    end
    initial begin #2000000;$display("FAIL M1: test timeout");$fatal(1);end
endmodule
