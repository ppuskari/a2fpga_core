// A2FPGA ROMless Media Mailbox M1 for a physical card in Apple slot 3.
// Apple IIe AND IIgs: C0B0-C0BF (no slot ROM, no C300 or C800 claim).
// Apple -> MCU command latch and 256-byte byte-stream FIFO.
// BL616 SPI XFER SPACE 7 is independent of SPACE 6 (stereo HDMI PCM).
//
// MCU XFER7 read addresses:
//   0x800000..0x80000f: mirror of Apple-facing register snapshot
//   0x800010: pending command; 0x800011: MCU status;
//   0x800012: accepted Apple reads lo, 0x800013: reads hi;
//   0x800014: accepted Apple writes lo, 0x800015: writes hi;
//   0x800016: expected file length byte0, ...0x800019 byte3
//   0x000000...: pop one buffered Apple byte per SPI XFER read.
// MCU XFER7 write addresses:
//   0x800010: acknowledge pending command, DATA must equal sequence (+A)
//   0x800011: set command result visible at Apple +C
//   0x800012: set MCU status bits (ready=bit0, playing=bit1,
//             diagnostic transfer active=bit2).
//   0x800013: write 0xA5 to clear FIFO/counters, only when idle
//   0x800020: inject Apple command for MCU-only loopback (if idle)
//   0x800021: inject Apple FIFO byte for MCU-only loopback
//
// Apple $C0B0..BF:
//   +0 'M'; +1 'B'; +2 protocol v1;
//   +3 status: [0]MCU ready, [1]FIFO free, [2]cmd pending,
//              [3]FIFO overflow, [4]playing, [5]test upload active,
//              [6]command rejected, [7]reserved;
//   +4 write command (read last accepted command)
//   +5 write data to FIFO (read always 0)
//   +6/7 FIFO free LE; +8/9 FIFO queued LE
//   +A command sequence; +B acknowledged sequence;
//   +C last result; +D/E overflow count LE; +F 0xA5.
// Apple has no ROM, no IRQ, no DOC/mouse/GLU dependencies.
// Reset by FPGA device reset, NOT Apple /RESET: music stays autonomous.
module media_mailbox_slot3 #(
    parameter integer FIFO_AW=8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        apple_sel_i,
    input  wire        apple_rw_n_i,
    input  wire        apple_write_strobe_i,
    input  wire [3:0]  apple_reg_i,
    input  wire [7:0]  apple_wdata_i,
    output wire        apple_read_o,
    output reg  [7:0]  apple_rdata_o,

    input  wire        spi_wr_i,
    input  wire [23:0] spi_wr_addr_i,
    input  wire [7:0]  spi_wr_data_i,
    input  wire        spi_rd_i,
    input  wire [23:0] spi_rd_addr_i,
    output reg         spi_rd_valid_o,
    output reg  [7:0]  spi_rd_data_o
);
    localparam integer DEPTH=(1<<FIFO_AW);
    wire apple_wr=apple_sel_i && !apple_rw_n_i && apple_write_strobe_i;
    assign apple_read_o=apple_sel_i && apple_rw_n_i;

    reg [7:0] fifo [0:DEPTH-1];
    reg [FIFO_AW:0] wrptr_r,rdptr_r;
    wire [FIFO_AW:0] count_w=wrptr_r-rdptr_r;
    wire [FIFO_AW:0] free_w=(FIFO_AW+1)'(DEPTH)-count_w;

    reg [7:0] cmd_r,cmd_seq_r,ack_seq_r,cmd_result_r,mcu_status_r;
    reg cmd_pending_r,cmd_rejected_r;
    reg [15:0] fifo_overflow_r,apple_reads_r,apple_writes_r;
    reg apple_selected_d;
    reg [31:0] transfer_size_r;

    wire app_cmd_wr=apple_wr && apple_reg_i==4'h4;
    wire mcu_cmd_wr=spi_wr_i && spi_wr_addr_i==24'h800020;
    wire cmd_wr=app_cmd_wr || mcu_cmd_wr;
    wire [7:0] cmd_wdata=app_cmd_wr?apple_wdata_i:spi_wr_data_i;

    wire app_fifo_wr=apple_wr && apple_reg_i==4'h5;
    wire mcu_fifo_wr=spi_wr_i && spi_wr_addr_i==24'h800021;
    wire fifo_wr=app_fifo_wr || mcu_fifo_wr;
    wire [7:0] fifo_wdata=app_fifo_wr?apple_wdata_i:spi_wr_data_i;

    wire stream_pop=spi_rd_i && !spi_rd_addr_i[23];
    wire reset_fifo=spi_wr_i && spi_wr_addr_i==24'h800013 &&
                    spi_wr_data_i==8'hA5 && !cmd_pending_r;

    wire [7:0] status_w={
        1'b0,cmd_rejected_r,mcu_status_r[2],
        mcu_status_r[1],(|fifo_overflow_r),cmd_pending_r,
        (count_w<DEPTH),mcu_status_r[0]
    };

    function automatic [7:0] register_byte(input [3:0] a);
    begin
        case(a)
            4'h0:register_byte=8'h4D; // M
            4'h1:register_byte=8'h42; // B
            4'h2:register_byte=8'h01;
            4'h3:register_byte=status_w;
            4'h4:register_byte=cmd_r;
            4'h5:register_byte=8'h00;
            4'h6:register_byte=free_w[7:0];
            4'h7:register_byte=8'(free_w>>8);
            4'h8:register_byte=count_w[7:0];
            4'h9:register_byte=8'(count_w>>8);
            4'hA:register_byte=cmd_seq_r;
            4'hB:register_byte=ack_seq_r;
            4'hC:register_byte=cmd_result_r;
            4'hD:register_byte=fifo_overflow_r[7:0];
            4'hE:register_byte=fifo_overflow_r[15:8];
            4'hF:register_byte=8'hA5;
        endcase
    end
    endfunction

    // always_comb evaluates at time zero as well as on address changes;
    // a read of +0 is valid even when the address never toggled beforehand.
    always_comb begin
        apple_rdata_o=register_byte(apple_reg_i);
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            wrptr_r<=0;rdptr_r<=0;
            cmd_r<=0;cmd_seq_r<=0;ack_seq_r<=0;cmd_result_r<=0;
            mcu_status_r<=0;cmd_pending_r<=0;cmd_rejected_r<=0;
            fifo_overflow_r<=0;
            apple_reads_r<=0;apple_writes_r<=0;
            apple_selected_d<=0;transfer_size_r<=0;
            spi_rd_valid_o<=0;spi_rd_data_o<=8'hff;
        end else begin
            apple_selected_d<=apple_sel_i;
            if(apple_sel_i && apple_rw_n_i && !apple_selected_d)
                apple_reads_r<=apple_reads_r+1'b1;
            if(apple_wr)
                apple_writes_r<=apple_writes_r+1'b1;

            spi_rd_valid_o<=0;
            if(spi_rd_i) begin
                spi_rd_valid_o<=1'b1;
                if(!spi_rd_addr_i[23]) begin
                    if(count_w!=0) begin
                        spi_rd_data_o<=fifo[rdptr_r[FIFO_AW-1:0]];
                        rdptr_r<=rdptr_r+1'b1;
                    end else
                        spi_rd_data_o<=8'hFF;
                end else begin
                    case(spi_rd_addr_i[4:0])
                        5'h10:spi_rd_data_o<=cmd_pending_r?cmd_r:8'h00;
                        5'h11:spi_rd_data_o<=mcu_status_r;
                        5'h12:spi_rd_data_o<=apple_reads_r[7:0];
                        5'h13:spi_rd_data_o<=apple_reads_r[15:8];
                        5'h14:spi_rd_data_o<=apple_writes_r[7:0];
                        5'h15:spi_rd_data_o<=apple_writes_r[15:8];
                        5'h16:spi_rd_data_o<=transfer_size_r[7:0];
                        5'h17:spi_rd_data_o<=transfer_size_r[15:8];
                        5'h18:spi_rd_data_o<=transfer_size_r[23:16];
                        5'h19:spi_rd_data_o<=transfer_size_r[31:24];
                        default:spi_rd_data_o<=register_byte(spi_rd_addr_i[3:0]);
                    endcase
                end
            end

            if(apple_wr) begin
                case(apple_reg_i)
                    4'h8:transfer_size_r[7:0]<=apple_wdata_i;
                    4'h9:transfer_size_r[15:8]<=apple_wdata_i;
                    4'hA:transfer_size_r[23:16]<=apple_wdata_i;
                    4'hB:transfer_size_r[31:24]<=apple_wdata_i;
                    default:begin end
                endcase
            end

            if(cmd_wr) begin
                if(!cmd_pending_r) begin
                    cmd_r<=cmd_wdata;
                    cmd_seq_r<=cmd_seq_r+1'b1;
                    cmd_pending_r<=1'b1;
                    cmd_rejected_r<=0;
                end else
                    cmd_rejected_r<=1'b1;
            end

            if(fifo_wr) begin
                if(count_w<DEPTH) begin
                    fifo[wrptr_r[FIFO_AW-1:0]]<=fifo_wdata;
                    wrptr_r<=wrptr_r+1'b1;
                end else if(fifo_overflow_r!=16'hFFFF)
                    fifo_overflow_r<=fifo_overflow_r+1'b1;
            end

            if(spi_wr_i) begin
                case(spi_wr_addr_i)
                    24'h800010:if(cmd_pending_r &&
                                    spi_wr_data_i==cmd_seq_r)begin
                                   ack_seq_r<=spi_wr_data_i;
                                   cmd_pending_r<=0;
                               end
                    24'h800011:cmd_result_r<=spi_wr_data_i;
                    24'h800012:mcu_status_r<=spi_wr_data_i[2:0];
                    default:begin end
                endcase
            end

            if(reset_fifo) begin
                wrptr_r<=0;rdptr_r<=0;
                fifo_overflow_r<=0;cmd_rejected_r<=0;
            end
        end
    end
endmodule
