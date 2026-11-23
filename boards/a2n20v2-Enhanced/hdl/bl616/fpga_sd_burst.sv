// M3: autonomous receive-only 512-byte SD SPI data block staging.
//
// The MCU still sends CMD17/CMD18 and waits for each 0xFE token with
// the proven 0x6C-0x6E legacy register path. Once the token is received,
// it writes 0xA1 to register 0x6E; this engine generates 512 dummy-FF
// transfers through the existing fpga_sd_spi master, retaining CS# low.
// The engine buffers all received bytes, and exposes them at:
//   XFER SPACE0, address 24'h800000..8001FF, 512 bytes.
// Firmware reads the completed buffer with one bulk XFER, then consumes
// the two SD CRC bytes through the legacy path.
//
// This does NOT change the SPI protocol, other XFER spaces, SD pins,
// audio/DOC/SSI paths or existing low 256-byte SPACE0 RAM.
//
// Commands: START=0xA1; ABORT=0xAF.
// Status: [7] supported, [6] completed, [5] active, [4] error.
// The connector preserves bit[0] as legacy SD_BYTE_BUSY.
//
// A stuck/missing SD byte cannot hold the MCU's shared FPGA SPI link:
// the FPGA uses its own 54MHz clock and the SD SPI master autonomously.
module fpga_sd_burst (
    input wire clk,
    input wire rst_n,
    input wire start_i,
    input wire abort_i,
    input wire cs_n_i,
    input wire sd_busy_i,
    input wire [7:0] sd_rx_data_i,
    output reg sd_tx_start_o,
    output wire [7:0] sd_tx_data_o,
    output wire active_o,
    output reg complete_o,
    output reg error_o,
    input wire rd_req_i,
    input wire [8:0] rd_addr_i,
    output reg rd_valid_o,
    output reg [7:0] rd_data_o
);
    localparam [2:0] IDLE = 3'd0,
                     LAUNCH = 3'd1,
                     WAIT_BUSY = 3'd2,
                     WAIT_DONE = 3'd3,
                     COMPLETE = 3'd4;
    reg [2:0] state;
    reg [8:0] byte_index;
    reg [7:0] buffer [0:511];

    assign sd_tx_data_o = 8'hFF;
    assign active_o = (state == LAUNCH ||
                       state == WAIT_BUSY || state == WAIT_DONE);

    // One synchronous read port. The connector's read response mux
    // consumes rd_valid_o on the following system clock.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_valid_o <= 1'b0;
            rd_data_o <= 8'h00;
        end else begin
            rd_valid_o <= rd_req_i;
            if (rd_req_i)
                rd_data_o <= buffer[rd_addr_i];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            byte_index <= 9'd0;
            sd_tx_start_o <= 1'b0;
            complete_o <= 1'b0;
            error_o <= 1'b0;
        end else begin
            sd_tx_start_o <= 1'b0;
            if (abort_i) begin
                state <= IDLE;
                complete_o <= 1'b0;
                error_o <= 1'b0;
            end else if (start_i) begin
                if (active_o || sd_busy_i || cs_n_i) begin
                    // Never overlap a legacy SD byte or start with CS# high.
                    state <= IDLE;
                    complete_o <= 1'b1;
                    error_o <= 1'b1;
                end else begin
                    byte_index <= 9'd0;
                    complete_o <= 1'b0;
                    error_o <= 1'b0;
                    state <= LAUNCH;
                end
            end else if (active_o && cs_n_i) begin
                state <= COMPLETE;
                complete_o <= 1'b1;
                error_o <= 1'b1;
            end else begin
                case (state)
                    IDLE: ;
                    LAUNCH: begin
                        if (!sd_busy_i) begin
                            sd_tx_start_o <= 1'b1;
                            state <= WAIT_BUSY;
                        end
                    end
                    WAIT_BUSY: begin
                        if (sd_busy_i)
                            state <= WAIT_DONE;
                    end
                    WAIT_DONE: begin
                        if (!sd_busy_i) begin
                            buffer[byte_index] <= sd_rx_data_i;
                            if (byte_index == 9'd511) begin
                                state <= COMPLETE;
                                complete_o <= 1'b1;
                            end else begin
                                byte_index <= byte_index + 9'd1;
                                state <= LAUNCH;
                            end
                        end
                    end
                    COMPLETE: ;
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule
