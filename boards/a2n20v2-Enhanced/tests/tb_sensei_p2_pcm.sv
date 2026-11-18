`timescale 1ns/1ps
module tb_sensei_p2_pcm;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,native_enabled=1;
    reg spi_wr=0,spi_rd=0,ready=0;
    reg [23:0] wr_addr=0,rd_addr=0;
    reg [7:0] wr_data=0;
    wire rd_valid,slot_rd,doc_owner,doc_wr,pcm_owner,pcm_wr;
    wire [7:0] rd_data,slot_data,doc_addr,doc_data;
    wire [20:0] pcm_addr;
    wire [31:0] pcm_data;
    integer accepted=0;
    sensei_tracker_bridge #(.CLOCK_HZ(1000),.FIFO_AW(3)) dut(
        .clk(clk),.rst_n(rst_n),.native_enabled_i(native_enabled),
        .slot_selected_i(1'b0),.slot_addr_i(4'b0),
        .slot_data_i(8'b0),.slot_rw_n_i(1'b1),
        .slot_write_strobe_i(1'b0),.slot_read_o(slot_rd),
        .slot_rdata_o(slot_data),
        .spi_wr_i(spi_wr),.spi_wr_addr_i(wr_addr),
        .spi_wr_data_i(wr_data),.spi_rd_i(spi_rd),
        .spi_rd_addr_i(rd_addr),.spi_rd_valid_o(rd_valid),
        .spi_rd_data_o(rd_data),.doc_owner_o(doc_owner),
        .doc_wr_o(doc_wr),.doc_addr_o(doc_addr),
        .doc_data_o(doc_data),
        .pcm_ram_owner_o(pcm_owner),.pcm_ram_wr_o(pcm_wr),
        .pcm_ram_addr_o(pcm_addr),.pcm_ram_data_o(pcm_data),
        .pcm_ram_ready_i(ready)
    );

    task wr(input [7:0] addr,input [7:0] value);
        @(negedge clk);
        wr_addr={16'b0,addr};wr_data=value;spi_wr=1;
        @(negedge clk);
        spi_wr=0;
    endtask
    task rd(input [7:0] addr,input [7:0] expected);
        @(negedge clk);
        rd_addr={16'b0,addr};spi_rd=1;
        @(posedge clk);#1;
        if(!rd_valid || rd_data!==expected)
            $fatal(1,"P2 PCM SPI %h observed %h expected %h",
                   addr,rd_data,expected);
        @(negedge clk);spi_rd=0;
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        rd(8'h26,8'h42); // feature flag
        wr(8'h1F,8'hA5); // open PCM DMA
        rd(8'h20,8'h01);
        if (!pcm_owner || pcm_wr) $fatal(1,"DMA owner missing");
        wr(8'h18,8'h07); // DOC bytes 28-31
        wr(8'h19,8'h00);
        wr(8'h1A,8'h80);
        wr(8'h1B,8'h91);
        wr(8'h1C,8'hA2);
        wr(8'h1D,8'hB3);
        wr(8'h1E,8'hA5);
        if (!pcm_wr || pcm_addr!==7 || pcm_data!==32'hB3A29180)
            $fatal(1,"PCM memory write mismatch: addr=%h data=%h",pcm_addr,pcm_data);
        repeat(5) @(negedge clk);
        rd(8'h20,8'h03); // upload+pending
        rd(8'h21,8'h00);
        ready=1;
        @(negedge clk);
        ready=0;
        repeat(3) @(negedge clk);
        if(pcm_wr) $fatal(1,"DMA ignored SDRAM ready");
        rd(8'h21,8'h01);
        rd(8'h22,8'h00);
        rd(8'h23,8'h00);
        wr(8'h1F,8'h5A); // done after ack
        if(pcm_owner) $fatal(1,"DMA port owner leaked");
        rd(8'h20,8'h08); // completed
        if(doc_owner) $fatal(1,"DOC register owner active prematurely");
        // Reject writes outside begin/end window and record error.
        wr(8'h1E,8'hA5);
        rd(8'h23,8'h01);
        wr(8'h1F,8'h00); // abort/clear DMA state
        native_enabled=0;
        repeat(2) @(negedge clk);
        if(pcm_owner || pcm_wr) $fatal(1,"native isolation failed");
        $display("PASS P2 PCM: SPI staging, byte order, SDRAM handshake, ack and release");
        $finish;
    end
endmodule
