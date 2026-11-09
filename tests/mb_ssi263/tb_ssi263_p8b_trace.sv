`timescale 1ns/1ps
// Same 1MHz XCK register stream / 3x50ms windows as p8b_compare_trace.c.
// Test executes entire new P8 chip, never the legacy waveform playback.
module tb_ssi263_p8b_trace #(
    parameter bit VOICE_ENABLE=1,
    parameter bit NOISE_ENABLE=1
);
    logic clk=0;
    always #5 clk=~clk;
    logic rst_n=0, xck=0,wr=0;
    logic [3:0] xck_div=0;
    always @(posedge clk) begin
      if(!rst_n)begin xck<=0;xck_div<=0;end
      else if(xck_div==11)begin xck<=1;xck_div<=0;end
      else begin xck<=0;xck_div<=xck_div+1'b1;end
    end
    logic [2:0] regno=0;
    logic [7:0] din=0;
    wire ar_n,powered;
    wire [5:0] phoneme;
    wire [7:0] r3;
    wire signed [15:0] pcm;
    integer fd, samples=0;
    integer nonzero=0, peak=0, maxjump=0;
    integer oldsample=0;
    integer current,absval,jump;
    ssi263_p8_chip #(
       .LOGIC_HZ(12_000_000),
       .OUTPUT_HZ(50_000),
       .EXCITATION_VOICE_ENABLE(VOICE_ENABLE),
       .EXCITATION_NOISE_ENABLE(NOISE_ENABLE)
    ) dut (
       .clk_i(clk),.reset_n_i(rst_n),.xck_tick_i(xck),
       .write_i(wr),.reg_i(regno),.data_i(din),
       .ar_n_o(ar_n),.powered_o(powered),.phoneme_o(phoneme),
       .r3_debug_o(r3),.pcm_o(pcm)
    );

    task automatic write_reg(input logic [2:0] r,input logic [7:0] v);
        @(negedge clk);wr=1;regno=r;din=v;
        @(negedge clk);wr=0;
    endtask
    task automatic capture(input integer n);
        integer got;
        begin
            got=0;
            while(got<n) begin
                @(posedge clk);
                #1;
                if(dut.sample_valid_o) begin
                    if(^pcm===1'bx) $fatal(1,"Unknown PCM at sample %0d",samples);
                    $fwrite(fd,"%c%c",pcm[7:0],pcm[15:8]);
                    current=$signed(pcm);
                    absval=(current<0)?-current:current;
                    if(absval>peak)peak=absval;
                    if(current!=0)nonzero++;
                    jump=current-oldsample;
                    if(jump<0)jump=-jump;
                    if(jump>maxjump)maxjump=jump;
                    oldsample=current;
                    samples++;got++;
                end
            end
        end
    endtask

    initial begin
        fd=$fopen("p8b_trace.pcm","wb");
        if(fd==0) $fatal(1,"Cannot open P8B trace");
        repeat(8) @(negedge clk);rst_n=1;
        write_reg(3'd4,8'he8);
        write_reg(3'd2,8'ha8);
        write_reg(3'd1,8'h6f);
        write_reg(3'd0,8'h60);
        write_reg(3'd3,8'h7f);
        if(!powered || phoneme!=6'h20) $fatal(1,"P8B start missing");
        capture(2500);
        write_reg(3'd0,8'h88);
        capture(2500);
        write_reg(3'd0,8'h44);
        capture(2500);
        write_reg(3'd0,8'h30); // open unvoiced FA=15 fricative
        capture(2500);
        write_reg(3'd3,8'h80);
        repeat(5) @(negedge clk);
        if(powered || !ar_n || pcm!==0) $fatal(1,"P8B poweroff mute/IRQ failed");
        if(samples!=10000) $fatal(1,"Wrong sample count");
        if(!VOICE_ENABLE && !NOISE_ENABLE && nonzero!=0)
            $fatal(1,"Audio without excitation: %0d samples",nonzero);
        if((VOICE_ENABLE || NOISE_ENABLE) && nonzero<50)
            $fatal(1,"Voice excitation failed: %0d nonzero",nonzero);
        $fclose(fd);
        $display("P8B TRACE PASS: voice=%0d noise=%0d samples=%0d nonzero=%0d peak=%0d maxjump=%0d",
                 VOICE_ENABLE,NOISE_ENABLE,samples,nonzero,peak,maxjump);
        $finish;
    end
    initial begin #80000000; $fatal(1,"P9 FIR trace timeout"); end
endmodule
