// M2 duplex slot-3 mailbox test, preserving M1 v1 Apple ABI.
// Device clock is faster than Apple /SEL; samples early and late in phi0.
module tb_media_mailbox_m2;
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
        #1;val=ardata;
        repeat(6) @(negedge clk);
        if(ardata!==val)$fatal(1,"M2 Apple data changed within phi0");
        asel=0;
        repeat(3) @(negedge clk);
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
        @(negedge clk);if(!svalid)$fatal(1,"M2 SPI read invalid");
        val=srdata;sr=0;
        repeat(2) @(negedge clk);
    end endtask
    reg [7:0] v;
    integer i;
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        spi_read(24'h80001d,v);if(v!==8'h4d)$fatal(1,"M2 FPGA signature M");
        spi_read(24'h80001e,v);if(v!==8'h32)$fatal(1,"M2 FPGA signature 2");
        apple_read(2,v);if(v!==8'h01)$fatal(1,"M1 Apple version changed");
        apple_read(3,v);if(v!==8'h02)$fatal(1,"M1 initial status changed");
        spi_write(24'h800030,8'h41);
        spi_write(24'h800030,8'h42);
        spi_write(24'h800030,8'h43);
        apple_read(3,v);if(!(v & 8'h80))$fatal(1,"M2 reply ready not asserted");
        spi_read(24'h80001a,v);if(v!==8'h03)$fatal(1,"M2 reply count 3");
        apple_read(5,v);if(v!==8'h41)$fatal(1,"M2 Apple first reply byte");
        apple_read(5,v);if(v!==8'h42)$fatal(1,"M2 Apple second reply byte");
        apple_read(5,v);if(v!==8'h43)$fatal(1,"M2 Apple third reply byte");
        apple_read(3,v);if(v & 8'h80)$fatal(1,"M2 reply-ready failed to clear");
        apple_read(5,v);if(v!==8'h00)$fatal(1,"M2 empty reply value");
        // Apple writes through C0B5 still go into the ORIGINAL upload FIFO.
        apple_write(5,8'hAA);
        spi_read(24'h000000,v);if(v!==8'hAA)$fatal(1,"M1 upload broken by M2");
        // Fill small (8B) test reply buffer and prove overflow latch + clear.
        for(i=0;i<8;i=i+1)spi_write(24'h800030,8'(i+1));
        spi_write(24'h800030,8'hFE);
        spi_read(24'h80001c,v);if(v!==8'h01)$fatal(1,"M2 overflow not reported");
        spi_write(24'h800031,8'hA5);
        spi_read(24'h80001a,v);if(v!==0)$fatal(1,"M2 reply reset failed");
        spi_read(24'h80001c,v);if(v!==0)$fatal(1,"M2 overflow reset failed");
        apple_read(3,v);if(v & 8'h80)$fatal(1,"M2 ready after reset");
        $display("PASS M2: reply FIFO, held data through Apple phi0, single pop");
        $display("PASS M2: independent upload FIFO, protocol1 ABI, overflow/reset");
        $finish;
    end
    initial begin #2000000;$fatal(1,"M2 test timeout");end
endmodule
