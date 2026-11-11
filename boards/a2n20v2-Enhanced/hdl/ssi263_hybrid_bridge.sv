// P10 BL616 SSI263 hybrid transport. 54 MHz logic clock domain.
//
// XFER SPACE 4: PCM16 little-endian stream (write address 0 onward);
//   status is read from address 0x800000 (24 bytes).
//   write 0x800000 => clear PCM ring and error counters.
//   write 0x800002 <= {0,1} => RESUME, SUSPEND PCM delivery.
//   Suspended audio outputs digital zero without underrun accounting, and
//   event XCK tracking + Apple SSI registers remain live and independent.
//   status bytes 26/27 => 0xB7 capability + bit0 suspended ACK.
// XFER SPACE 5: 8-byte SSI CPU-write events (read, address 0 onward).
//   Event bytes: reg, data, seq_lo, seq_hi, tick[7:0]..tick[31:24].
//   Consuming byte 7 pops an event. Never pop on an empty queue.
// Bus-derived SSI events/XCK belong to the FPGA; MCU PCM has no control
// over VIA CA1 or Apple-visible register timing.
//
// PCM output remains locked to the real 44.1k HDMI audio enable. A programmable
// 1/2/4 sample-hold divider consumes MCU speech at 44.1/22.05/11.025 kHz.
// DOC piano, AY FX, HDMI framing and SSI chip register/A-R timing are unchanged.
// Legacy P10 MCU sees the same 24-byte status and starts at 44.1k (mode 0).
// New MCU sees status extension 0xA6/mode at offsets 24/25; a write to
// SPACE4:0x800001 sets mode 0/1/2 and atomically flushes the PCM FIFO.
// All SPI mem strobes are already in the 54MHz connector domain.
module ssi263_hybrid_bridge #(
    parameter integer PCM_DEPTH=2048,
    parameter integer START_WATERMARK=512,
    parameter integer EVENT_DEPTH=256
)(
    input wire clk_i,
    input wire reset_n_i,
    input wire audio_tick_pixel_i,
    input wire speech_powered_i,
    input wire xck_tick_i,
    input wire event_valid_i,
    input wire [2:0] event_reg_i,
    input wire [7:0] event_data_i,
    input wire spi_wr_i,
    input wire [2:0] spi_wr_space_i,
    input wire [23:0] spi_wr_addr_i,
    input wire [7:0] spi_wr_data_i,
    input wire spi_rd_i,
    input wire [2:0] spi_rd_space_i,
    input wire [23:0] spi_rd_addr_i,
    output logic spi_rd_valid_o,
    output logic [7:0] spi_rd_data_o,
    output logic signed [15:0] speech_pcm_o
);
    // Fixed powers-of-two give cheap pointer arithmetic.
    localparam integer PCM_AW=$clog2(PCM_DEPTH);
    localparam integer EVT_AW=$clog2(EVENT_DEPTH);
    logic [PCM_AW:0] pcm_wrptr_r, pcm_rdptr_r;
    logic [15:0] pcm_mem [0:PCM_DEPTH-1];
    wire [PCM_AW:0] pcm_count_w=pcm_wrptr_r-pcm_rdptr_r;
    wire [PCM_AW:0] pcm_free_w=PCM_DEPTH-pcm_count_w;
    logic [7:0] pcm_lo_r;
    logic pcm_lo_valid_r,playing_r,pcm_suspended_r;
    logic [1:0] pcm_rate_mode_r,pcm_div_phase_r;
    wire pcm_consume_tick_w = pcm_rate_mode_r==2'd0 ||
        (pcm_rate_mode_r==2'd1 && !pcm_div_phase_r[0]) ||
        (pcm_rate_mode_r==2'd2 && pcm_div_phase_r==2'd0);
    logic speech_power_prev_r;
    logic [15:0] underrun_r,overrun_r;

    logic [EVT_AW:0] evt_wrptr_r,evt_rdptr_r;
    wire [EVT_AW:0] evt_count_w=evt_wrptr_r-evt_rdptr_r;
    logic [63:0] evt_mem[0:EVENT_DEPTH-1];
    logic [63:0] evt_read_latched_r;
    wire [63:0] evt_head_w=evt_mem[evt_rdptr_r[EVT_AW-1:0]];
    logic [15:0] evt_seq_r,evt_overflow_r;
    logic [31:0] xck_count_r;
    logic [2:0] sample_sync_r;
    wire audio_tick_w=sample_sync_r[2] && !sample_sync_r[1];

    wire pcm_stream_wr_w=spi_wr_i && spi_wr_space_i==3'd4 &&
                           !spi_wr_addr_i[23] && !pcm_suspended_r;
    wire pcm_reset_w=spi_wr_i && spi_wr_space_i==3'd4 &&
                       spi_wr_addr_i==24'h800000;
    wire pcm_rate_set_w=spi_wr_i && spi_wr_space_i==3'd4 &&
                         spi_wr_addr_i==24'h800001 &&
                         spi_wr_data_i<=8'd2;
    wire pcm_suspend_cmd_w=spi_wr_i && spi_wr_space_i==3'd4 &&
                           spi_wr_addr_i==24'h800002 &&
                           spi_wr_data_i<=8'd1;
    wire pcm_write_sample_w=pcm_stream_wr_w && spi_wr_addr_i[0] &&
                            pcm_lo_valid_r && (pcm_count_w<PCM_DEPTH);
    wire evt_pop_w=spi_rd_i && spi_rd_space_i==3'd5 &&
                   spi_rd_addr_i[2:0]==3'd7 && evt_count_w!=0;
    wire evt_push_w=event_valid_i && (evt_count_w<EVENT_DEPTH);

    function automatic [7:0] event_byte(
        input [63:0] word_i,input [2:0] index_i
    );
        case(index_i)
            3'd0:event_byte=word_i[7:0];
            3'd1:event_byte=word_i[15:8];
            3'd2:event_byte=word_i[23:16];
            3'd3:event_byte=word_i[31:24];
            3'd4:event_byte=word_i[39:32];
            3'd5:event_byte=word_i[47:40];
            3'd6:event_byte=word_i[55:48];
            default:event_byte=word_i[63:56];
        endcase
    endfunction

    // Combinational status, one 24-byte read from 0x800000.
    // Magic SP, version 1, flags, PCM count/free, event count,
    // underrun/overrun/overflow counters, event sequence and watermark.
    function automatic [7:0] status_byte(input [4:0] idx);
        case(idx)
          0:status_byte=8'h53;
          1:status_byte=8'h50;
          2:status_byte=8'd1;
          3:status_byte={4'b0,(evt_overflow_r!=0),(underrun_r!=0),speech_powered_i,playing_r};
          4:status_byte=pcm_count_w[7:0];
          5:status_byte={{(8-(PCM_AW+1-8)){1'b0}},pcm_count_w[PCM_AW:8]};
          6:status_byte=pcm_free_w[7:0];
          7:status_byte={{(8-(PCM_AW+1-8)){1'b0}},pcm_free_w[PCM_AW:8]};
          8:status_byte=evt_count_w[7:0];
          9:status_byte={{(8-(EVT_AW+1-8)){1'b0}},evt_count_w[EVT_AW:8]};
          10:status_byte=underrun_r[7:0];
          11:status_byte=underrun_r[15:8];
          12:status_byte=overrun_r[7:0];
          13:status_byte=overrun_r[15:8];
          14:status_byte=evt_overflow_r[7:0];
          15:status_byte=evt_overflow_r[15:8];
          16:status_byte=evt_seq_r[7:0];
          17:status_byte=evt_seq_r[15:8];
          18:status_byte=START_WATERMARK[7:0];
          19:status_byte=(START_WATERMARK>>8);
          20:status_byte=pcm_wrptr_r[7:0];
          21:status_byte=pcm_rdptr_r[7:0];
          22:status_byte=8'h50; // protocol "P1" marker
          23:status_byte=8'h31;
          24:status_byte=8'hA6; // R6 PCM rate-select capability marker
          25:status_byte={6'b0,pcm_rate_mode_r}; // 0=44k,1=22k,2=11k
          26:status_byte=8'hB7; // R11 explicit PCM suspend capability
          27:status_byte={7'b0,pcm_suspended_r}; // acknowledged state
          default:status_byte=8'hff;
        endcase
    endfunction

    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            pcm_wrptr_r<=0;pcm_rdptr_r<=0;
            pcm_lo_r<=0;pcm_lo_valid_r<=0;
            pcm_suspended_r<=0;
            pcm_rate_mode_r<=0;pcm_div_phase_r<=0;
            speech_power_prev_r<=0;
            speech_pcm_o<=0;playing_r<=0;
            underrun_r<=0;overrun_r<=0;
            evt_wrptr_r<=0;evt_rdptr_r<=0;
            evt_seq_r<=0;evt_overflow_r<=0;
            evt_read_latched_r<=0;
            xck_count_r<=0;
            sample_sync_r<=0;
            spi_rd_valid_o<=0;spi_rd_data_o<=8'hff;
        end else begin
            sample_sync_r<={sample_sync_r[1:0],audio_tick_pixel_i};
            speech_power_prev_r<=speech_powered_i;
            spi_rd_valid_o<=0;

            if(xck_tick_i)xck_count_r<=xck_count_r+1'b1;

            if(event_valid_i)begin
                evt_seq_r<=evt_seq_r+1'b1;
                if(evt_push_w)begin
                    // Producer's elapsed XCK stamp and strict CPU write order.
                    evt_mem[evt_wrptr_r[EVT_AW-1:0]]<=
                       {xck_count_r,evt_seq_r,event_data_i,{5'b0,event_reg_i}};
                    evt_wrptr_r<=evt_wrptr_r+1'b1;
                end else if(evt_overflow_r!=16'hffff)
                    evt_overflow_r<=evt_overflow_r+1'b1;
            end
            if(evt_pop_w)evt_rdptr_r<=evt_rdptr_r+1'b1;

            if(spi_rd_i && spi_rd_space_i==3'd5)begin
                spi_rd_valid_o<=1;
                if(evt_count_w==0)spi_rd_data_o<=8'hff;
                else begin
                    if(spi_rd_addr_i[2:0]==3'd0)begin
                        evt_read_latched_r<=evt_head_w;
                        spi_rd_data_o<=evt_head_w[7:0];
                    end else
                        spi_rd_data_o<=event_byte(evt_read_latched_r,
                                                  spi_rd_addr_i[2:0]);
                end
            end else if(spi_rd_i && spi_rd_space_i==3'd4)begin
                spi_rd_valid_o<=1;
                spi_rd_data_o<=spi_rd_addr_i[23] ?
                    status_byte(spi_rd_addr_i[4:0]) : 8'hff;
            end

            // Never replay buffered old-phoneme PCM across CTL powerdown.
            // Reset the FIFO even if the BL616 is delayed or absent.
            if(pcm_reset_w || pcm_rate_set_w || pcm_suspend_cmd_w ||
               (speech_power_prev_r && !speech_powered_i))begin
                if(pcm_rate_set_w)pcm_rate_mode_r<=spi_wr_data_i[1:0];
                // Preserve the paused state across an Apple powerdown edge;
                // the MCU will acknowledge any next write before re-priming.
                if(pcm_suspend_cmd_w)pcm_suspended_r<=spi_wr_data_i[0];
                else if(pcm_reset_w || pcm_rate_set_w)pcm_suspended_r<=0;
                pcm_div_phase_r<=0;
                pcm_wrptr_r<=0;pcm_rdptr_r<=0;
                pcm_lo_valid_r<=0;playing_r<=0;
                speech_pcm_o<=0;
                underrun_r<=0;overrun_r<=0;
            end else begin
                if(pcm_stream_wr_w)begin
                    if(!spi_wr_addr_i[0])begin
                        pcm_lo_r<=spi_wr_data_i;
                        pcm_lo_valid_r<=1;
                    end else begin
                        pcm_lo_valid_r<=0;
                        if(pcm_write_sample_w)begin
                            pcm_mem[pcm_wrptr_r[PCM_AW-1:0]]<=
                                {spi_wr_data_i,pcm_lo_r};
                            pcm_wrptr_r<=pcm_wrptr_r+1'b1;
                        end else if(overrun_r!=16'hffff)
                            overrun_r<=overrun_r+1'b1;
                    end
                end
                // Actual HDMI 44.1 kHz strobe. Low-rate speech holds its
                // previous 16-bit sample between 2x/4x source consumption
                // ticks. No MCU duplication and no extra SPI traffic.
                if(audio_tick_w)begin
                    case(pcm_rate_mode_r)
                      2'd0:pcm_div_phase_r<=0;
                      2'd1:pcm_div_phase_r<={1'b0,~pcm_div_phase_r[0]};
                      default:pcm_div_phase_r<=pcm_div_phase_r+2'd1;
                    endcase
                    if(!speech_powered_i || pcm_suspended_r)
                        speech_pcm_o<=0;
                    else if(pcm_consume_tick_w)begin
                        if(playing_r && pcm_count_w!=0)begin
                            speech_pcm_o<=pcm_mem[pcm_rdptr_r[PCM_AW-1:0]];
                            pcm_rdptr_r<=pcm_rdptr_r+1'b1;
                        end else begin
                            speech_pcm_o<=0;
                            if(playing_r && pcm_count_w==0)begin
                                playing_r<=0;
                                if(underrun_r!=16'hffff)
                                    underrun_r<=underrun_r+1'b1;
                            end else if(pcm_count_w>=START_WATERMARK)
                                playing_r<=1;
                        end
                    end
                end
            end
        end
    end
endmodule
