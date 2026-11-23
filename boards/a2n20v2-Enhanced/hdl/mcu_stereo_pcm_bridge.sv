// Direct BL616 stereo PCM -> HDMI transport. NO DOC involvement.
// XFER SPACE 6: stream signed little-endian 16-bit L,R frames to address 0;
//   0x800000: reset FIFO, underrun/overflow counters, disable output
//   0x800001: 1=enable playback, 0=mute/reset play gate (FIFO retained)
// Read 0x800000..0x80000f: 'P','C',version,flags,level lo/hi,
//   free lo/hi, underruns lo/hi, overflow lo/hi, consumed frames u32.
// PCM timing derives solely from the existing HDMI 44.1 kHz sample strobe.
// This MUST NOT write GLU, DOC registers, sound RAM or audio personality.
module mcu_stereo_pcm_bridge #(
    parameter integer PCM_AW=11, // 2048 stereo frames = 8 KiB
    parameter integer START_WATERMARK=512
)(
    input wire clk,
    input wire rst_n,
    input wire audio_tick_pixel_i,
    input wire spi_wr_i,
    input wire [23:0] spi_wr_addr_i,
    input wire [7:0] spi_wr_data_i,
    input wire spi_rd_i,
    input wire [23:0] spi_rd_addr_i,
    output reg spi_rd_valid_o,
    output reg [7:0] spi_rd_data_o,
    output reg signed [15:0] pcm_left_o,
    output reg signed [15:0] pcm_right_o,
    // Optional M3 HDMI metering extension. Inputs are stable in this
    // module's clk domain; diagnostics never touch the PCM FIFO.
    input wire [15:0] hdmi_peak_left_i,
    input wire [15:0] hdmi_peak_right_i,
    input wire [7:0] hdmi_clip_history_i,
    input wire hdmi_diag_valid_i
);
    localparam integer DEPTH=1<<PCM_AW;
    localparam [PCM_AW:0] DEPTH_COUNT=DEPTH;
    localparam [PCM_AW:0] START_COUNT=START_WATERMARK;
    reg [31:0] pcm_mem [0:DEPTH-1];
    reg [PCM_AW:0] wrptr_r,rdptr_r;
    wire [PCM_AW:0] count_w=wrptr_r-rdptr_r;
    wire [PCM_AW:0] free_w=DEPTH_COUNT-count_w;
    reg [23:0] frame_r;
    reg [15:0] underruns_r,overflows_r;
    reg [31:0] played_frames_r;
    // Capture whole 9-byte diagnostic read at address 0x800010 so a
    // 1Hz meter update cannot tear the L/R/clip snapshot mid-transfer.
    reg [40:0] hdmi_diag_latched_r;
    reg enabled_r,playing_r;
    reg [2:0] tick_sync_r;
    wire tick_w=tick_sync_r[2] && !tick_sync_r[1];
    wire ctrl_reset_w=spi_wr_i && spi_wr_addr_i==24'h800000;
    wire ctrl_enable_w=spi_wr_i && spi_wr_addr_i==24'h800001;
    wire stream_w=spi_wr_i && !spi_wr_addr_i[23];
    wire push_w=stream_w && spi_wr_addr_i[1:0]==2'b11 &&
                count_w<DEPTH_COUNT;
    wire pop_w=tick_w && enabled_r && (playing_r ||
                count_w>=START_COUNT) && count_w!=0;
    // The 4-byte frame assembler is deliberately driven by monotonically
    // increasing XFER byte addresses; every new SPI block begins at 0.
    always @(posedge clk) begin
        if(!rst_n) begin
            wrptr_r<=0;rdptr_r<=0;frame_r<=0;
            enabled_r<=0;playing_r<=0;
            underruns_r<=0;overflows_r<=0;played_frames_r<=0;
            tick_sync_r<=0;pcm_left_o<=0;pcm_right_o<=0;
            spi_rd_valid_o<=0;spi_rd_data_o<=0;
            hdmi_diag_latched_r<=0;
        end else begin
            tick_sync_r<={tick_sync_r[1:0],audio_tick_pixel_i};
            spi_rd_valid_o<=0;
            if(spi_rd_i && spi_rd_addr_i[23]) begin
                spi_rd_valid_o<=1;
                if (spi_rd_addr_i == 24'h800010)
                    hdmi_diag_latched_r <= {
                        hdmi_diag_valid_i, hdmi_clip_history_i,
                        hdmi_peak_left_i, hdmi_peak_right_i
                    };
                case(spi_rd_addr_i[4:0])
                    5'h0:spi_rd_data_o<=8'h50; // P
                    5'h1:spi_rd_data_o<=8'h43; // C
                    5'h2:spi_rd_data_o<=8'h01; // v1
                    5'h3:spi_rd_data_o<={6'b0,playing_r,enabled_r};
                    5'h4:spi_rd_data_o<=count_w[7:0];
                    5'h5:spi_rd_data_o<=8'(count_w>>8);
                    5'h6:spi_rd_data_o<=free_w[7:0];
                    5'h7:spi_rd_data_o<=8'(free_w>>8);
                    5'h8:spi_rd_data_o<=underruns_r[7:0];
                    5'h9:spi_rd_data_o<=underruns_r[15:8];
                    5'ha:spi_rd_data_o<=overflows_r[7:0];
                    5'hb:spi_rd_data_o<=overflows_r[15:8];
                    5'hc:spi_rd_data_o<=played_frames_r[7:0];
                    5'hd:spi_rd_data_o<=played_frames_r[15:8];
                    5'he:spi_rd_data_o<=played_frames_r[23:16];
                    5'h0f:spi_rd_data_o<=played_frames_r[31:24];
                    // M3 optional extension 0x800010..0x800018:
                    // 'H','M',version,clip,L lo/hi,R lo/hi,valid.
                    // Old 16-byte 'PC v1' status remains byte-identical.
                    5'h10:spi_rd_data_o<=8'h48; // H
                    5'h11:spi_rd_data_o<=8'h4d; // M
                    5'h12:spi_rd_data_o<=8'h01; // v1
                    5'h13:spi_rd_data_o<=hdmi_diag_latched_r[39:32];
                    5'h14:spi_rd_data_o<=hdmi_diag_latched_r[31:24];
                    5'h15:spi_rd_data_o<=hdmi_diag_latched_r[23:16];
                    5'h16:spi_rd_data_o<=hdmi_diag_latched_r[15:8];
                    5'h17:spi_rd_data_o<=hdmi_diag_latched_r[7:0];
                    5'h18:spi_rd_data_o<={7'b0,hdmi_diag_latched_r[40]};
                endcase
            end
            if(ctrl_reset_w) begin
                wrptr_r<=0;rdptr_r<=0;frame_r<=0;
                enabled_r<=0;playing_r<=0;
                underruns_r<=0;overflows_r<=0;played_frames_r<=0;
                pcm_left_o<=0;pcm_right_o<=0;
            end else begin
                if(ctrl_enable_w) begin
                    enabled_r<=spi_wr_data_i[0];
                    if(!spi_wr_data_i[0]) begin
                        playing_r<=0;
                        pcm_left_o<=0;pcm_right_o<=0;
                    end
                end
                if(stream_w) begin
                    case(spi_wr_addr_i[1:0])
                        2'b00:frame_r[7:0]<=spi_wr_data_i;
                        2'b01:frame_r[15:8]<=spi_wr_data_i;
                        2'b10:frame_r[23:16]<=spi_wr_data_i;
                        default:if(push_w) begin
                            pcm_mem[wrptr_r[PCM_AW-1:0]]<={spi_wr_data_i,frame_r};
                            wrptr_r<=wrptr_r+1'b1;
                        end else if(overflows_r!=16'hffff)
                            overflows_r<=overflows_r+1'b1;
                    endcase
                end
                if(tick_w) begin
                    if(!enabled_r) begin
                        pcm_left_o<=0;pcm_right_o<=0;
                    end else if(pop_w) begin
                        pcm_left_o<=pcm_mem[rdptr_r[PCM_AW-1:0]][15:0];
                        pcm_right_o<=pcm_mem[rdptr_r[PCM_AW-1:0]][31:16];
                        rdptr_r<=rdptr_r+1'b1;
                        played_frames_r<=played_frames_r+1'b1;
                        playing_r<=1'b1;
                    end else begin
                        pcm_left_o<=0;pcm_right_o<=0;
                        if(playing_r) begin
                            playing_r<=0;
                            if(underruns_r!=16'hffff)
                                underruns_r<=underruns_r+1'b1;
                        end
                    end
                end
            end
        end
    end
endmodule
