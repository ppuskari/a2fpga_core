`timescale 1ns/1ps
module tb_packet_direct_capture;
    reg clk=0, reset=1, audio_tick=0;
    reg packet_enable=0, video_field_end=0;
    reg [4:0] packet_pixel_counter=0;
    reg [15:0] pcm [1:0];
    wire [23:0] header;
    wire [55:0] sub [3:0];
    always #5 clk=~clk;
    packet_picker #(
        .VIDEO_ID_CODE(2), .VIDEO_RATE(27.0e6),
        .AUDIO_BIT_WIDTH(16), .AUDIO_RATE(44100)
    ) dut (
        .clk_pixel(clk),.clk_audio(audio_tick),.reset(reset),
        .video_field_end(video_field_end),
        .packet_enable(packet_enable),
        .packet_pixel_counter(packet_pixel_counter),
        .audio_sample_word(pcm),.header(header),.sub(sub)
    );
    task automatic send_sample(input [15:0] l, input [15:0] r);
        begin
            @(negedge clk);
            pcm[0]=l;
            pcm[1]=r;
            audio_tick=1;
            @(negedge clk);
            audio_tick=0;
            repeat(2) @(negedge clk);
        end
    endtask
    integer i;
    initial begin
        pcm[0]=0;pcm[1]=0;
        repeat(3) @(negedge clk);
        reset=0;
        for(i=0;i<4;i=i+1) send_sample(16'h1000+i,16'h4000+i);
        #1;
        if(dut.samples_remaining!==0 || dut.sample_buffer_current!==1 ||
           dut.sample_buffer_ready!==1)
            $fatal(1,"First 4-sample packet did not publish");
        for(i=0;i<4;i=i+1) begin
            if(dut.audio_sample_word_buffer[0][i][0] !== (24'h100000+(i<<8)) ||
               dut.audio_sample_word_buffer[0][i][1] !== (24'h400000+(i<<8)))
                $fatal(1,"PCM value/order wrong index=%0d",i);
        end
        for(i=0;i<4;i=i+1) send_sample(16'h2000+i,16'h5000+i);
        #1;
        if(dut.samples_remaining!==0 || dut.sample_buffer_current!==0)
            $fatal(1,"Second 4-sample packet didn't switch buffers");
        for(i=0;i<4;i=i+1) begin
            if(dut.audio_sample_word_buffer[1][i][0] !== (24'h200000+(i<<8)) ||
               dut.audio_sample_word_buffer[1][i][1] !== (24'h500000+(i<<8)))
                $fatal(1,"Second PCM buffer corrupted index=%0d",i);
        end
        $display("PASS: same-domain packet buffer captures all 4 stereo samples in order");
        $finish;
    end
    initial begin #200000; $fatal(1,"packet direct simulation timeout"); end
endmodule
