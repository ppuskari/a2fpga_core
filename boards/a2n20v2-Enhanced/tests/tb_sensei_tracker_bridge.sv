`timescale 1ns/1ps
module tb_sensei_tracker_bridge;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, native=1, slot_sel=0, slot_rw=1, slot_wr=0;
    reg [3:0] slot_addr=0;
    reg [7:0] slot_data=0;
    wire slot_rd;
    wire [7:0] slot_out;
    reg spi_wr=0, spi_rd=0;
    reg [23:0] wr_addr=0, rd_addr=0;
    reg [7:0] wr_data=0;
    wire rd_valid,doc_owner,doc_wr;
    wire [7:0] rd_data,doc_addr,doc_data;
    integer writes=0;

    sensei_tracker_bridge #(.CLOCK_HZ(1000),.FIFO_AW(3)) dut (
        .clk(clk),.rst_n(rst_n),.native_enabled_i(native),
        .slot_selected_i(slot_sel),.slot_addr_i(slot_addr),
        .slot_data_i(slot_data),.slot_rw_n_i(slot_rw),
        .slot_write_strobe_i(slot_wr),.slot_read_o(slot_rd),
        .slot_rdata_o(slot_out),
        .spi_wr_i(spi_wr),.spi_wr_addr_i(wr_addr),
        .spi_wr_data_i(wr_data),.spi_rd_i(spi_rd),
        .spi_rd_addr_i(rd_addr),.spi_rd_valid_o(rd_valid),
        .spi_rd_data_o(rd_data),
        .doc_owner_o(doc_owner),.doc_wr_o(doc_wr),
        .doc_addr_o(doc_addr),.doc_data_o(doc_data)
    );
    always @(posedge clk) begin
        if (doc_wr) begin
            writes=writes+1;
            if (doc_addr!=8'h41 || doc_data!=8'h79)
                $fatal(1,"Unexpected DOC write %h %h",doc_addr,doc_data);
        end
    end
    task host_write(input [3:0] addr,input [7:0] data);
        @(negedge clk);
        slot_sel=1;slot_rw=0;slot_wr=1;slot_addr=addr;slot_data=data;
        @(negedge clk);
        slot_sel=0;slot_wr=0;slot_rw=1;
    endtask
    task host_read_check(input [3:0] addr,input [7:0] expect);
        @(negedge clk);
        slot_sel=1;slot_rw=1;slot_addr=addr;
        #1;
        if (!slot_rd || slot_out!==expect)
            $fatal(1,"Slot %h got %h expected %h",addr,slot_out,expect);
        @(negedge clk);slot_sel=0;
    endtask
    task transfer(input [7:0] addr,input [7:0] data);
        @(negedge clk);
        spi_wr=1;wr_addr={16'd0,addr};wr_data=data;
        @(negedge clk);
        spi_wr=0;
    endtask
    task read_check(input [7:0] addr,input [7:0] expected);
        @(negedge clk);
        spi_rd=1;rd_addr={16'd0,addr};
        @(posedge clk);#1;
        if (!rd_valid || rd_data!==expected)
            $fatal(1,"SPI %h got %h expected %h",addr,rd_data,expected);
        @(negedge clk);spi_rd=0;
    endtask

    reg [15:0] target;
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        host_read_check(4'hA,8'h53);
        host_read_check(4'hB,8'h1D);
        host_write(4'hD,8'h00);
        host_write(4'hC,8'h01);
        host_read_check(4'hD,8'h01); // sequence increments
        read_check(8'h02,8'h01);
        read_check(8'h03,8'h01);
        transfer(8'h05,8'h02); // MCU playing
        host_read_check(4'hC,8'h02);
        transfer(8'h16,8'h01); // exclusive native DOC ownership
        if(!doc_owner) $fatal(1,"DOC ownership not asserted");
        target=dut.millis_r+16'd65;
        transfer(8'h10,target[7:0]);
        transfer(8'h11,target[15:8]);
        transfer(8'h12,8'h41);
        transfer(8'h13,8'h79);
        transfer(8'h14,8'hA5);
        read_check(8'h06,8'h01); // one pending event
        repeat(75) @(negedge clk);
        if (writes!=1) $fatal(1,"Expected one scheduled write got %0d",writes);
        read_check(8'h06,8'h00);
        read_check(8'h0A,8'h01);
        transfer(8'h16,8'h00);
        if(doc_owner) $fatal(1,"DOC ownership did not release");
        host_write(4'hC,8'h02);
        read_check(8'h02,8'h02);
        native=0;
        repeat(2) @(negedge clk);
        if (slot_rd || doc_owner) $fatal(1,"native-mode isolation failed");
        $display("PASS P1D: CPU mailbox, SPI6 status, FPGA deadline, DOC ownership and isolation");
        $finish;
    end
endmodule
