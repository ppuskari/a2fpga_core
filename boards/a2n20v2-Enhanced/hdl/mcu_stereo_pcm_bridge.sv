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
    output reg signed [15:0] pcm_right_o
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
        end else begin
            tick_sync_r<={tick_sync_r[1:0],audio_tick_pixel_i};
            spi_rd_valid_o<=0;
            if(spi_rd_i && spi_rd_addr_i[23]) begin
                spi_rd_valid_o<=1;
                case(spi_rd_addr_i[3:0])
                    4'h0:spi_rd_data_o<=8'h50; // P
                    4'h1:spi_rd_data_o<=8'h43; // C
                    4'h2:spi_rd_data_o<=8'h01; // v1
                    4'h3:spi_rd_data_o<={6'b0,playing_r,enabled_r};
                    4'h4:spi_rd_data_o<=count_w[7:0];
                    4'h5:spi_rd_data_o<=8'(count_w>>8);
                    4'h6:spi_rd_data_o<=free_w[7:0];
                    4'h7:spi_rd_data_o<=8'(free_w>>8);
                    4'h8:spi_rd_data_o<=underruns_r[7:0];
                    4'h9:spi_rd_data_o<=underruns_r[15:8];
                    4'ha:spi_rd_data_o<=overflows_r[7:0];
                    4'hb:spi_rd_data_o<=overflows_r[15:8];
                    4'hc:spi_rd_data_o<=played_frames_r[7:0];
                    4'hd:spi_rd_data_o<=played_frames_r[15:8];
                    4'he:spi_rd_data_o<=played_frames_r[23:16];
                    4'hf:spi_rd_data_o<=played_frames_r[31:24];
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
