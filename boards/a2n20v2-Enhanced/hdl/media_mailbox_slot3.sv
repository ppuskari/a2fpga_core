// A2FPGA ROMless Media Mailbox M1+M2 for physical Apple slot 3.
// M2 adds a separate MCU->Apple reply FIFO; original M1 register ABI stays.
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

    // M1 bring-up: force flip-flops rather than invoking Gowin's RAM
    // inference engine.  The register array is 256*8=2048 bits, and
    // Gowin can otherwise infer an incompatible RAM read/write mode.
    // Reconsider BRAM only after both physical Apple buses are proven.
    reg [7:0] fifo [0:DEPTH-1] /* synthesis syn_ramstyle = "registers" */;
    reg [FIFO_AW:0] wrptr_r,rdptr_r;
    // M2 response FIFO; retire a read only after its Apple bus phase ends.
    reg [7:0] reply_fifo[0:DEPTH-1] /* synthesis syn_ramstyle = "registers" */;
    reg [FIFO_AW:0] reply_wrptr_r,reply_rdptr_r;
    reg reply_read_seen_r;
    reg [7:0] reply_read_latched_r;
    reg reply_overflow_r;
    wire [FIFO_AW:0] reply_count_w=reply_wrptr_r-reply_rdptr_r;
    wire reply_available_w=(reply_count_w!=0);
    wire [FIFO_AW:0] count_w=wrptr_r-rdptr_r;
    localparam [FIFO_AW:0] DEPTH_W = (1 << FIFO_AW);
    wire [FIFO_AW:0] free_w=DEPTH_W-count_w;
    // Simple unsigned zero extension: no SystemVerilog size casts,
    // including in the 8-byte regression parameterization.
    wire [15:0] count16_w=count_w;
    wire [15:0] free16_w=free_w;

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

    wire reply_byte_select=apple_sel_i && apple_rw_n_i && apple_reg_i==4'h5;
    wire [7:0] status_w={
        reply_available_w,cmd_rejected_r,mcu_status_r[2],
        mcu_status_r[1],(|fifo_overflow_r),cmd_pending_r,
        (count_w<DEPTH),mcu_status_r[0]
    };


    // No automatic function and no cross-referenced sensitivity tracking:
    // each read port is a plain, independently decoded 16:1 multiplexer.
    always @* begin
        apple_rdata_o=8'h00;
        case(apple_reg_i)
            4'h0:apple_rdata_o=8'h4D;
            4'h1:apple_rdata_o=8'h42;
            4'h2:apple_rdata_o=8'h01;
            4'h3:apple_rdata_o=status_w;
            4'h4:apple_rdata_o=cmd_r;
            4'h5:apple_rdata_o=reply_read_seen_r ? reply_read_latched_r :
                                  (reply_available_w ? reply_fifo[reply_rdptr_r[FIFO_AW-1:0]] : 8'h00);
            4'h6:apple_rdata_o=free16_w[7:0];
            4'h7:apple_rdata_o=free16_w[15:8];
            4'h8:apple_rdata_o=count16_w[7:0];
            4'h9:apple_rdata_o=count16_w[15:8];
            4'hA:apple_rdata_o=cmd_seq_r;
            4'hB:apple_rdata_o=ack_seq_r;
            4'hC:apple_rdata_o=cmd_result_r;
            4'hD:apple_rdata_o=fifo_overflow_r[7:0];
            4'hE:apple_rdata_o=fifo_overflow_r[15:8];
            4'hF:apple_rdata_o=8'hA5;
            default:apple_rdata_o=8'h00;
        endcase
    end

    reg [7:0] spi_register_byte_w;
    always @* begin
        spi_register_byte_w=8'h00;
        case(spi_rd_addr_i[3:0])
            4'h0:spi_register_byte_w=8'h4D;
            4'h1:spi_register_byte_w=8'h42;
            4'h2:spi_register_byte_w=8'h01;
            4'h3:spi_register_byte_w=status_w;
            4'h4:spi_register_byte_w=cmd_r;
            4'h5:spi_register_byte_w=8'h00;
            4'h6:spi_register_byte_w=free16_w[7:0];
            4'h7:spi_register_byte_w=free16_w[15:8];
            4'h8:spi_register_byte_w=count16_w[7:0];
            4'h9:spi_register_byte_w=count16_w[15:8];
            4'hA:spi_register_byte_w=cmd_seq_r;
            4'hB:spi_register_byte_w=ack_seq_r;
            4'hC:spi_register_byte_w=cmd_result_r;
            4'hD:spi_register_byte_w=fifo_overflow_r[7:0];
            4'hE:spi_register_byte_w=fifo_overflow_r[15:8];
            4'hF:spi_register_byte_w=8'hA5;
            default:spi_register_byte_w=8'h00;
        endcase
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            wrptr_r<=0;rdptr_r<=0;
            reply_wrptr_r<=0;reply_rdptr_r<=0;
            reply_read_seen_r<=0;reply_read_latched_r<=0;
            reply_overflow_r<=0;
            cmd_r<=0;cmd_seq_r<=0;ack_seq_r<=0;cmd_result_r<=0;
            mcu_status_r<=0;cmd_pending_r<=0;cmd_rejected_r<=0;
            fifo_overflow_r<=0;
            apple_reads_r<=0;apple_writes_r<=0;
            apple_selected_d<=0;transfer_size_r<=0;
            spi_rd_valid_o<=0;spi_rd_data_o<=8'hff;
        end else begin
            apple_selected_d<=apple_sel_i;
            // Hold the selected response byte stable throughout phi0;
            // pop at end-of-select, not at its beginning. No double-pop
            // when an accelerated Apple IIgs stretches a read bus phase.
            if(reply_byte_select && !reply_read_seen_r) begin
                reply_read_seen_r<=1'b1;
                reply_read_latched_r<=reply_available_w ?
                    reply_fifo[reply_rdptr_r[FIFO_AW-1:0]]:8'h00;
            end else if(!apple_sel_i && reply_read_seen_r) begin
                reply_read_seen_r<=1'b0;
                if(reply_available_w)
                    reply_rdptr_r<=reply_rdptr_r+1'b1;
            end
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
                        5'h1A:spi_rd_data_o<=reply_count_w[7:0];
                        5'h1B:spi_rd_data_o<=reply_count_w[FIFO_AW];
                        5'h1C:spi_rd_data_o<={7'b0,reply_overflow_r};
                        default:spi_rd_data_o<=spi_register_byte_w;
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
                    // M2 response path, separate from upload FIFO.
                    24'h800030:begin
                        if(reply_count_w<DEPTH_W) begin
                            reply_fifo[reply_wrptr_r[FIFO_AW-1:0]]<=spi_wr_data_i;
                            reply_wrptr_r<=reply_wrptr_r+1'b1;
                        end else reply_overflow_r<=1'b1;
                    end
                    24'h800031:if(spi_wr_data_i==8'hA5) begin
                        reply_wrptr_r<=0;reply_rdptr_r<=0;
                        reply_read_seen_r<=0;reply_overflow_r<=0;
                    end
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
