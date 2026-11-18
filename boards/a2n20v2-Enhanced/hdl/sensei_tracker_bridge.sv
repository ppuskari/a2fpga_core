// SenseiPlay8 P1D -- isolated 6502 -> MCU -> FPGA timed DOC transport.
// No modifications to the legacy Mockingboard or IIgs DOC register map.
// Copyright (c) 2026 Petar Puskarich and contributors.
module sensei_tracker_bridge #(
    parameter integer CLOCK_HZ = 54_000_000,
    parameter integer FIFO_AW = 6
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        native_enabled_i,

    // Virtual native DOC slot, offsets $A-$F only.
    input  wire        slot_selected_i,
    input  wire [3:0]  slot_addr_i,
    input  wire [7:0]  slot_data_i,
    input  wire        slot_rw_n_i,
    input  wire        slot_write_strobe_i,
    output wire        slot_read_o,
    output reg  [7:0]  slot_rdata_o,

    // MCU XFER SPACE 6, synchronous to clk. Address 0x00-0x1F.
    input  wire        spi_wr_i,
    input  wire [23:0] spi_wr_addr_i,
    input  wire [7:0]  spi_wr_data_i,
    input  wire        spi_rd_i,
    input  wire [23:0] spi_rd_addr_i,
    output reg         spi_rd_valid_o,
    output reg  [7:0]  spi_rd_data_o,

    // Exclusive DOC register owner. Original IIe DOC samples may be
    // preloaded BEFORE owner is claimed. PCM DMA is deliberately deferred.
    output wire        doc_owner_o,
    output reg         doc_wr_o,
    output reg  [7:0]  doc_addr_o,
    output reg  [7:0]  doc_data_o
);
    localparam integer FIFO_DEPTH = 1 << FIFO_AW;
    localparam integer MS_DIVIDER = (CLOCK_HZ >= 1000) ? CLOCK_HZ/1000 : 1;
    localparam [FIFO_AW:0] DEPTH_COUNT = FIFO_DEPTH;

    reg [31:0] divider_r;
    reg [15:0] millis_r;
    reg [7:0] host_command_r, host_arg_r, host_seq_r;
    reg [7:0] mcu_state_r;
    reg owner_r;

    reg [15:0] staging_time_r;
    reg [7:0] staging_addr_r, staging_data_r;
    reg [15:0] event_time_r [0:FIFO_DEPTH-1];
    reg [7:0] event_addr_r [0:FIFO_DEPTH-1];
    reg [7:0] event_data_r [0:FIFO_DEPTH-1];
    reg [FIFO_AW-1:0] read_ptr_r, write_ptr_r;
    reg [FIFO_AW:0] count_r;
    reg [7:0] overflow_r;
    reg [15:0] played_r;

    wire host_write = native_enabled_i && slot_selected_i &&
                      !slot_rw_n_i && slot_write_strobe_i;
    assign slot_read_o = native_enabled_i && slot_selected_i &&
                         slot_rw_n_i && (slot_addr_i >= 4'hA);
    assign doc_owner_o = native_enabled_i && owner_r;

    wire full_w = (count_r == DEPTH_COUNT);
    wire empty_w = (count_r == 0);
    wire push_w = spi_wr_i && (spi_wr_addr_i[7:0] == 8'h14) &&
                  (spi_wr_data_i == 8'hA5) && !full_w;
    wire due_w = doc_owner_o && !empty_w &&
                 ($signed(millis_r - event_time_r[read_ptr_r]) >= 0);
    wire flush_w = spi_wr_i && (spi_wr_addr_i[7:0] == 8'h15) &&
                   (spi_wr_data_i == 8'hA5);
    wire release_w = spi_wr_i && (spi_wr_addr_i[7:0] == 8'h16) &&
                     !spi_wr_data_i[0];

    always @(*) begin
        slot_rdata_o = 8'h00;
        case (slot_addr_i)
            4'hA: slot_rdata_o = 8'h53; // 'S'
            4'hB: slot_rdata_o = 8'h1D; // tracker P1D protocol revision
            4'hC: slot_rdata_o = mcu_state_r;
            4'hD: slot_rdata_o = host_seq_r;
            4'hE: slot_rdata_o = count_r;
            4'hF: slot_rdata_o = overflow_r;
            default: ;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            divider_r <= 0;
            millis_r <= 0;
            host_command_r <= 0;
            host_arg_r <= 0;
            host_seq_r <= 0;
            mcu_state_r <= 0;
            owner_r <= 0;
            staging_time_r <= 0;
            staging_addr_r <= 0;
            staging_data_r <= 0;
            read_ptr_r <= 0;
            write_ptr_r <= 0;
            count_r <= 0;
            overflow_r <= 0;
            played_r <= 0;
            doc_wr_o <= 0;
            doc_addr_o <= 0;
            doc_data_o <= 0;
            spi_rd_valid_o <= 0;
            spi_rd_data_o <= 8'hFF;
        end else begin
            doc_wr_o <= 1'b0;
            spi_rd_valid_o <= spi_rd_i;
            if (divider_r == MS_DIVIDER - 1) begin
                divider_r <= 0;
                millis_r <= millis_r + 1'b1;
            end else divider_r <= divider_r + 1'b1;

            if (!native_enabled_i) begin
                owner_r <= 0;
                mcu_state_r <= 0;
                read_ptr_r <= 0;
                write_ptr_r <= 0;
                count_r <= 0;
            end else begin
                if (host_write) begin
                    case (slot_addr_i)
                        4'hC: begin
                            host_command_r <= slot_data_i;
                            host_seq_r <= host_seq_r + 1'b1;
                        end
                        4'hD: host_arg_r <= slot_data_i;
                        default: ;
                    endcase
                end

                if (spi_wr_i) begin
                    case (spi_wr_addr_i[7:0])
                        8'h05: mcu_state_r <= spi_wr_data_i;
                        8'h10: staging_time_r[7:0] <= spi_wr_data_i;
                        8'h11: staging_time_r[15:8] <= spi_wr_data_i;
                        8'h12: staging_addr_r <= spi_wr_data_i;
                        8'h13: staging_data_r <= spi_wr_data_i;
                        8'h16: owner_r <= spi_wr_data_i[0];
                        default: ;
                    endcase
                end

                if (flush_w || release_w) begin
                    read_ptr_r <= 0;
                    write_ptr_r <= 0;
                    count_r <= 0;
                end else begin
                    if (push_w) begin
                        event_time_r[write_ptr_r] <= staging_time_r;
                        event_addr_r[write_ptr_r] <= staging_addr_r;
                        event_data_r[write_ptr_r] <= staging_data_r;
                        write_ptr_r <= write_ptr_r + 1'b1;
                    end
                    if (due_w) begin
                        doc_addr_o <= event_addr_r[read_ptr_r];
                        doc_data_o <= event_data_r[read_ptr_r];
                        doc_wr_o <= 1'b1;
                        played_r <= played_r + 1'b1;
                        read_ptr_r <= read_ptr_r + 1'b1;
                    end
                    case ({push_w,due_w})
                        2'b10: count_r <= count_r + 1'b1;
                        2'b01: count_r <= count_r - 1'b1;
                        default: ;
                    endcase
                end
                if (spi_wr_i && spi_wr_addr_i[7:0] == 8'h14 &&
                    spi_wr_data_i == 8'hA5 && full_w &&
                    !flush_w && !release_w) begin
                    if (overflow_r != 8'hFF) overflow_r <= overflow_r + 1'b1;
                end

                // CPU panic: $C0CF=$A5 forcibly revokes MCU DOC ownership.
                // Old MCU images may fail to service the STOP command.
                // This allows the 6502 to issue StopDOC directly afterward.
                if (host_write && slot_addr_i == 4'hF &&
                    slot_data_i == 8'hA5) begin
                    owner_r <= 1'b0;
                    read_ptr_r <= 0;
                    write_ptr_r <= 0;
                    count_r <= 0;
                    mcu_state_r <= 8'd4;
                end
            end

            if (spi_rd_i) begin
                case (spi_rd_addr_i[7:0])
                    8'h00: spi_rd_data_o <= 8'h53;
                    8'h01: spi_rd_data_o <= 8'h1D;
                    8'h02: spi_rd_data_o <= host_command_r;
                    8'h03: spi_rd_data_o <= host_seq_r;
                    8'h04: spi_rd_data_o <= host_arg_r;
                    8'h05: spi_rd_data_o <= mcu_state_r;
                    8'h06: spi_rd_data_o <= count_r;
                    8'h07: spi_rd_data_o <= overflow_r;
                    8'h08: spi_rd_data_o <= millis_r[7:0];
                    8'h09: spi_rd_data_o <= millis_r[15:8];
                    8'h0A: spi_rd_data_o <= played_r[7:0];
                    8'h0B: spi_rd_data_o <= played_r[15:8];
                    8'h0C: spi_rd_data_o <= {6'b0, owner_r, native_enabled_i};
                    default: spi_rd_data_o <= 8'h00;
                endcase
            end
        end
    end
endmodule
